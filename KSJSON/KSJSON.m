//
//  KSJSON.m
//  KSJSON
//
//  Created by Karl Stenerud on 10/29/11.
//  Copyright (c) 2011 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "KSJSON.h"

#import <objc/runtime.h>


#pragma mark Configuration

/* Initial sizes when deserializing containers.
 * Values get stored on the stack until this point, and then get transferred
 * to the heap.
 */
#define kDeserialize_DictionaryInitialSize 256
#define kDeserialize_ArrayInitialSize 256

// Dictionaries of this size or less get converted on the stack instead of heap.
#define kSerialize_DictStackSize 128

// Stack-based scratch buffer size (for creating certain objects).
#define kSerialize_ScratchBuffSize 1024

// Starting buffer size for the serialized JSON string.
#define kSerialize_InitialBuffSize 65536


#pragma mark Tokens

// JSON parsing tokens
#define ESCAPE_BEGIN '\\'
#define STRING_BEGIN '"'
#define STRING_END '"'
#define FALSE_BEGIN 'f'
#define NULL_BEGIN 'n'
#define TRUE_BEGIN 't'
#define ELEMENT_SEPARATOR ','
#define NAME_SEPARATOR ':'
#define ARRAY_BEGIN '['
#define ARRAY_END ']'
#define DICTIONARY_BEGIN '{'
#define DICTIONARY_END '}'


#pragma mark Macros

// Compiler hints for "if" statements
#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))


// Handles bridging and autoreleasing in ARC or non-ARC mode.
#if __has_feature(objc_arc)
    #define autoreleased(X) (X)
    #define cfautoreleased(X) ((__bridge_transfer id)(X))
#else
    #define autoreleased(X) [(X) autorelease]
    #define cfautoreleased(X) [((__bridge_transfer id)(X)) autorelease]
#endif


/** Skip whitespace. Advances CH until it's off any whitespace, or it reaches
 * the end of the buffer.
 *
 * @param CH A pointer to the next character in the buffer.
 * @param END A pointer to the end of the buffer.
 */
#define skipWhitespace(CH,END) for(;(CH) < (END) && isspace(*(CH));(CH)++) {}


#pragma mark Context & Helpers

/** Deserializing contextual information.
 */
typedef struct
{
    /** Current position in the JSON string. */
    unichar* pos;
    /** End of the JSON string. */
    unichar* end;
    /** Any error that has occurred. */
    __autoreleasing NSError** error;
} KSJSONDeserializeContext;


// Forward reference.
static CFTypeRef deserializeElement(KSJSONDeserializeContext* context);


/** Lookup table for converting hex values to integers.
 * 0x77 is used to mark invalid characters.
 */
static unichar g_hexConversion[] =
{
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77,
    0x77, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x77,
    0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77,
    0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77,
    0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77, 0x77,
    0x77, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
};
/** Length of the conversion table. */
static unsigned int g_hexConversionEnd = sizeof(g_hexConversion) / sizeof(*g_hexConversion);


/** Make an error object with the specified message.
 *
 * @param error Pointer to a location to store the error object.
 *
 * @param fmt The message to fill the error object with.
 */
static void makeError(NSError** error, NSString* fmt, ...)
{
    if(error != nil)
    {
        va_list args;
        va_start(args, fmt);
        NSString* desc = autoreleased([[NSString alloc] initWithFormat:fmt arguments:args]);
        va_end(args);
        *error = [NSError errorWithDomain:@"KSJSON"
                                     code:1
                                 userInfo:[NSDictionary dictionaryWithObject:desc
                                                                      forKey:NSLocalizedDescriptionKey]];
    }
}


#pragma mark -
#pragma mark Deserialization
#pragma mark -


#pragma mark String Deserialization

/** Parse a unicode sequence (\u1234), placing the decoded character in dst.
 *
 * @param start The start of the unicode sequence.
 *
 * @param dst Location to store the unicode character.
 *
 * @param error Where to store any errors should they occur (nil = ignore).
 *
 * @return true if parsing was successful. If false, error will contain an
 *         explanation.
 */
static bool parseUnicodeSequence(const unichar* start,
                                 unichar* dst,
                                 NSError** error)
{
    unichar accum = 0;
    const unichar* end = start + 4;
    for(const unichar* ch = start; ch < end; ch++)
    {
        unsigned int next = *ch - '0';
        unlikely_if(next < 0 ||
                    next >= g_hexConversionEnd ||
                    g_hexConversion[next] == 0x77)
        {
            makeError(error, @"Invalid unicode sequence");
            return false;
        }
        accum = (unichar)((accum << 4) + g_hexConversion[next]);
    }
    *dst = accum;
    return true;
}

/** Deserialize a string.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFStringRef deserializeString(KSJSONDeserializeContext* context)
{
    unichar* ch = context->pos;
    unlikely_if(*ch != '"')
    {
        makeError(context->error, @"Expected a string");
        return nil;
    }
    unlikely_if(ch[1] == '"')
    {
        // Empty string
        context->pos = ch + 2;
        return CFStringCreateWithCString(NULL,
                                         "",
                                         kCFStringEncodingUTF8);
    }

    ch++;
    unichar* start = ch;
    unichar* pStr = start;

    // Look for a closing quote
    for(;ch < context->end && *ch != '"'; ch++)
    {
        likely_if(*ch != '\\')
        {
            *pStr++ = *ch;
        }
        else
        {
            ch++;
            switch(*ch)
            {
                case '\\':
                case '/':
                case '"':
                    *pStr++ = *ch;
                    break;
                case 'b':
                    *pStr++ = '\b';
                    break;
                case 'f':
                    *pStr++ = '\f';
                    break;
                case 'n':
                    *pStr++ = '\n';
                    break;
                case 'r':
                    *pStr++ = '\r';
                    break;
                case 't':
                    *pStr++ = '\t';
                    break;
                case 'u':
                {
                    ch++;
                    unlikely_if(ch > context->end - 4)
                    {
                        makeError(context->error, @"Unterminated escape sequence");
                        return nil;
                    }
                    unlikely_if(!parseUnicodeSequence(ch, pStr++, context->error))
                    {
                        return nil;
                    }
                    ch += 3;
                    break;
                }
                default:
                    makeError(context->error, @"Invalid escape sequence");
                    return nil;
            }
        }
    }
    
    unlikely_if(ch >= context->end)
    {
        makeError(context->error, @"Unterminated string");
        return nil;
    }
    
    context->pos = ch + 1;
    return CFStringCreateWithCharacters(NULL,
                                        start,
                                        (CFIndex)(pStr - start));
}


#pragma mark Number Deserialization

/** Check if a character is valid for representing part of a floating point
 * number.
 *
 * @param ch The character to test.
 *
 * @return true if the character is valid for floating point.
 */
static bool isFPChar(unichar ch)
{
    switch(ch)
    {
        case '0': case '1': case '2': case '3': case '4':
        case '5': case '6': case '7': case '8': case '9':
        case '.': case 'e': case 'E': case '+': case '-':
            return true;
        default:
            return false;
    }
}


/** Deserialize a number.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFNumberRef deserializeNumber(KSJSONDeserializeContext* context)
{
    unichar* start = context->pos;
    unichar* ch = start;
    
    // First, try to do a simple integer conversion.
    long long accum = 0;
    long long sign = *ch == '-' ? -1 : 1;
    if(sign == -1)
    {
        ch++;
    }
    
    for(;ch < context->end && isdigit(*ch); ch++)
    {
        accum = accum * 10 + (*ch - '0');
        unlikely_if(accum < 0)
        {
            // Overflow
            break;
        }
    }
    
    if(!isFPChar(*ch))
    {
        accum *= sign;
        context->pos = ch;
        return CFNumberCreate(NULL, kCFNumberLongLongType, &accum);
    }
    
    // It's not a simple integer, so let NSDecimalNumber convert it.
    for(;ch < context->end && isFPChar(*ch); ch++)
    {
    }
    
    context->pos = ch;
    
    NSString* string = cfautoreleased(CFStringCreateWithCharacters(NULL, start, ch - start));
    return (__bridge_retained CFNumberRef)[[NSDecimalNumber alloc] initWithString:string];
}


#pragma mark Other Deserialization

/** Deserialize "false".
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFNumberRef deserializeFalse(KSJSONDeserializeContext* context)
{
    const unichar* ch = context->pos;
    unlikely_if(context->end - ch < 5)
    {
        makeError(context->error, @"Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(ch[1] == 'a' && ch[2] == 'l' && ch[3] == 's' && ch[4] == 'e'))
    {
        makeError(context->error, @"Invalid characters while parsing 'false'");
        return nil;
    }
    context->pos += 5;
    char no = 0;
    return CFNumberCreate(NULL, kCFNumberCharType, &no);
}
/** Deserialize "true".
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */

static CFNumberRef deserializeTrue(KSJSONDeserializeContext* context)
{
    const unichar* ch = context->pos;
    unlikely_if(context->end - ch < 4)
    {
        makeError(context->error, @"Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(ch[1] == 'r' && ch[2] == 'u' && ch[3] == 'e'))
    {
        makeError(context->error, @"Invalid characters while parsing 'true'");
        return nil;
    }
    context->pos += 4;
    char yes = 1;
    return CFNumberCreate(NULL, kCFNumberCharType, &yes);
}

/** Deserialize "null".
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFNullRef deserializeNull(KSJSONDeserializeContext* context)
{
    const unichar* ch = context->pos;
    unlikely_if(context->end - ch < 4)
    {
        makeError(context->error, @"Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(ch[1] == 'u' && ch[2] == 'l' && ch[3] == 'l'))
    {
        makeError(context->error, @"Invalid characters while parsing 'null'");
        return nil;
    }
    context->pos += 4;
    return kCFNull;
}


#pragma mark Array Deserialization

/** Lightweight resizable array. */
typedef struct
{
    /** Stack storage when the array is small enough. */
    CFTypeRef valuesOnStack[kDeserialize_ArrayInitialSize];
    /** Heap storage when the array is bigger. */
    CFTypeRef* values;
    /** Length of the array buffer. */
    unsigned int length;
    /** Index of the end of the array. */
    unsigned int index;
    /** If true, we are using valuesOnStack. */
    bool onStack;
} Array;


/** Initialize an array.
 *
 * @param array The array.
 */
static void arrayInit(Array* array)
{
    array->onStack = true;
    array->index = 0;
    array->length = sizeof(array->valuesOnStack) / sizeof(*array->valuesOnStack);
    array->values = array->valuesOnStack;
}

/** Add an object to an array.
 *
 * @param array The array to add to.
 *
 * @param value The object to add.
 *
 * @param error Holds any errors that occur (nil = ignore).
 *
 * @return true if the object was successfully added.
 */
static bool arrayAddValue(Array* array, CFTypeRef value, NSError** error)
{
    unlikely_if(array->index >= array->length)
    {
        array->length *= 2;
        if(array->onStack)
        {
            // Switching from stack to heap.
            array->values = malloc(array->length * sizeof(*array->values));
            unlikely_if(array->values == NULL)
            {
                makeError(error, @"Out of memory");
                return false;
            }
            array->onStack = false;
            memcpy(array->values, array->valuesOnStack, array->index * sizeof(*array->values));
        }
        else
        {
            // Already on the heap, so reallocate.
            array->values = realloc(array->values, array->length * sizeof(*array->values));
            unlikely_if(array->values == NULL)
            {
                makeError(error, @"Out of memory");
                return false;
            }
        }
    }
    array->values[array->index] = value;
    array->index++;
    return true;
}

/** Free an array. All objects will be released.
 *
 * @param array The array to free.
 */
static void arrayFree(Array* array)
{
    for(unsigned int i = 0; i < array->index; i++)
    {
        CFRelease(array->values[i]);
    }
    if(!array->onStack)
    {
        free(array->values);
    }
}

/** Deserialize an array.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFArrayRef deserializeArray(KSJSONDeserializeContext* context)
{
    context->pos++;
    Array array;
    arrayInit(&array);

    while(context->pos < context->end)
    {
        skipWhitespace(context->pos, context->end);
        unlikely_if(*context->pos == ARRAY_END)
        {
            context->pos++;
            CFTypeRef result = CFArrayCreate(NULL,
                                             array.values,
                                             (CFIndex)array.index,
                                             &kCFTypeArrayCallBacks);
            arrayFree(&array);
            return result;
        }
        CFTypeRef element = deserializeElement(context);
        unlikely_if(element == nil)
        {
            goto failed;
        }
        skipWhitespace(context->pos, context->end);
        likely_if(*context->pos == ELEMENT_SEPARATOR)
        {
            context->pos++;
        }
        arrayAddValue(&array, element, context->error);
    }
    makeError(context->error, @"Unterminated array");

failed:
    arrayFree(&array);
    return nil;
}


#pragma mark Dictionary Deserialization

/** Lightweight resizable "dictionary data holder". */
typedef struct
{
    /** Stack storage for keys when dictionary is small enough. */
    CFTypeRef keysOnStack[kDeserialize_DictionaryInitialSize];
    /** Stack storage for values when dictionary is small enough. */
    CFTypeRef valuesOnStack[kDeserialize_DictionaryInitialSize];
    /** Heap storage for keys when the array is bigger. */
    CFTypeRef* keys;
    /** Heap storage for values when the array is bigger. */
    CFTypeRef* values;
    /** Length of the dictionary buffer. */
    unsigned int length;
    /** Index of the end of the dictionary. */
    unsigned int index;
    /** If true, we are using keysOnStack and valuesOnStack. */
    bool onStack;
} Dictionary;


/** Initialize a dictionary.
 *
 * @param dict The dictionary to initialize.
 */
static void dictInit(Dictionary* dict)
{
    dict->onStack = true;
    dict->index = 0;
    dict->length = sizeof(dict->keysOnStack) / sizeof(*dict->keysOnStack);
    dict->keys = dict->keysOnStack;
    dict->values = dict->valuesOnStack;
}

/** Add a key-value pair to a dictionary.
 *
 * @param dict The dictionary to add to.
 *
 * @param key The key to add.
 *
 * @param value The object to add.
 *
 * @param error Holds any errors that occur (nil = ignore).
 *
 * @return true if the pair was successfully added.
 */
static bool dictAddKeyAndValue(Dictionary* dict, CFStringRef key, CFTypeRef value, NSError** error)
{
    unlikely_if(dict->index >= dict->length)
    {
        dict->length *= 2;
        if(dict->onStack)
        {
            // Switching from stack to heap.
            dict->keys = malloc(dict->length * sizeof(*dict->keys));
            dict->values = malloc(dict->length * sizeof(*dict->values));
            unlikely_if(dict->keys == NULL || dict->values == NULL)
            {
                makeError(error, @"Out of memory");
                return false;
            }
            dict->onStack = false;
            memcpy(dict->keys, dict->keysOnStack, dict->length * sizeof(*dict->keys));
            memcpy(dict->values, dict->valuesOnStack, dict->length * sizeof(*dict->values));
        }
        else
        {
            // Already on the heap, so reallocate.
            dict->keys = realloc(dict->keys, dict->length * sizeof(*dict->keys));
            dict->values = realloc(dict->values, dict->length * sizeof(*dict->values));
            unlikely_if(dict->keys == NULL || dict->values == NULL)
            {
                makeError(error, @"Out of memory");
                return false;
            }
        }
    }
    dict->keys[dict->index] = key;
    dict->values[dict->index] = value;
    dict->index++;
    return true;
}

/** Free a dictionary. All keys and objects will be released.
 *
 * @param dict The dictionary to free.
 */
static void dictFree(Dictionary* dict)
{
    for(unsigned int i = 0; i < dict->index; i++)
    {
        CFRelease(dict->keys[i]);
        CFRelease(dict->values[i]);
    }

    if(!dict->onStack)
    {
        free(dict->keys);
        free(dict->values);
    }
}

/** Deserialize a dictionary.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFDictionaryRef deserializeDictionary(KSJSONDeserializeContext* context)
{
    context->pos++;
    Dictionary dict;
    dictInit(&dict);
    
    while(context->pos < context->end)
    {
        skipWhitespace(context->pos, context->end);
        unlikely_if(*context->pos == DICTIONARY_END)
        {
            context->pos++;
            CFTypeRef result = CFDictionaryCreate(NULL,
                                                  dict.keys,
                                                  dict.values,
                                                  (CFIndex)dict.index,
                                                  &kCFTypeDictionaryKeyCallBacks,
                                                  &kCFTypeDictionaryValueCallBacks);
            dictFree(&dict);
            return result;
        }
        CFStringRef name = deserializeString(context);
        unlikely_if(name == nil)
        {
            goto failed;
        }
        skipWhitespace(context->pos, context->end);
        unlikely_if(*context->pos != NAME_SEPARATOR)
        {
            makeError(context->error, @"Expected name separator");
            goto failed;
        }
        context->pos++;
        CFTypeRef element = deserializeElement(context);
        unlikely_if(element == nil)
        {
            goto failed;
        }
        skipWhitespace(context->pos, context->end);
        likely_if(*context->pos == ELEMENT_SEPARATOR)
        {
            context->pos++;
        }
        unlikely_if(!dictAddKeyAndValue(&dict, name, element, context->error))
        {
            goto failed;
        }
    }
    
    makeError(context->error, @"Unterminated object");
    
failed:
    dictFree(&dict);
    return nil;
}


#pragma mark Top Level Deserialization

/** Deserialize an unknown element.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFTypeRef deserializeElement(KSJSONDeserializeContext* context)
{
    skipWhitespace(context->pos, context->end);
    
    switch(*context->pos)
    {
        case ARRAY_BEGIN:
            return deserializeArray(context);
        case DICTIONARY_BEGIN:
            return deserializeDictionary(context);
        case STRING_BEGIN:
            return deserializeString(context);
        case FALSE_BEGIN:
            return deserializeFalse(context);
        case TRUE_BEGIN:
            return deserializeTrue(context);
        case NULL_BEGIN:
            return deserializeNull(context);
        case '0': case '1': case '2': case '3': case '4':
        case '5': case '6': case '7': case '8': case '9':
        case '-': // Begin number
            return deserializeNumber(context);
    }
    makeError(context->error, @"Unexpected character: %c", *context->pos);
    return nil;
}

/** Begin the JSON deserialization process.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized container, or nil if an error occurred.
 */
static CFTypeRef deserializeJSON(KSJSONDeserializeContext* context)
{
    skipWhitespace(context->pos, context->end);
    switch(*context->pos)
    {
        case ARRAY_BEGIN:
            return deserializeArray(context);
            break;
        case DICTIONARY_BEGIN:
            return deserializeDictionary(context);
            break;
    }
    makeError(context->error, @"Unexpected character: %c", *context->pos);
    return nil;
}


#pragma mark -
#pragma mark Serialization
#pragma mark -


#pragma mark Serialization Helpers

/** Contextual information while serializing. */
typedef struct
{
    /** Buffer for the resulting string. */
    unichar* buffer;
    /** Scratch buffer for some operations. */
    unichar scratchBuffer[kSerialize_ScratchBuffSize];
    /** The size of the buffer. */
    unsigned int size;
    /** The current index into the buffer. */
    unsigned int index;
    /** Any error that has occurred. */
    __autoreleasing NSError** error;
} KSJSONSerializeContext;

static unichar g_false[] = {'f','a','l','s','e'};
static unichar g_true[] = {'t','r','u','e'};
static unichar g_null[] = {'n','u','l','l'};

// Forward declaration
static bool serializeObject(KSJSONSerializeContext* context, CFTypeRef object);


/** Initialize a serialization context.
 *
 * @param context The context to initialize.
 *
 * @return true if successful.
 */
static bool serializeInit(KSJSONSerializeContext* context)
{
    context->index = 0;
    context->size = kSerialize_InitialBuffSize;
    context->buffer = CFAllocatorAllocate(NULL,
                                          (CFIndex)(sizeof(context->buffer[0]) * context->size),
                                          0);
    unlikely_if(context->buffer == NULL)
    {
        makeError(context->error, @"Out of memory");
        return false;
    }
    return true;
}

/** Reallocate a bigger string buffer.
 *
 * @param context The serialization context.
 *
 * @param extraCount How many more characters we ned.
 *
 * @return true if successful.
 */
static bool serializeRealloc(KSJSONSerializeContext* context,
                             unsigned int extraCount)
{
    while(context->index + extraCount > context->size)
    {
        context->size *= 2;
    }
    context->buffer = CFAllocatorReallocate(NULL,
                                            context->buffer,
                                            (CFIndex)(sizeof(context->buffer[0]) * context->size),
                                            0);
    unlikely_if(context->buffer == NULL)
    {
        makeError(context->error, @"Out of memory");
        return false;
    }
    return true;
}

/** Finish the serialization process, returning the serializd JSON string.
 *
 * @param context The serialization context.
 *
 * @return The JSON string.
 */
static NSString* serializeFinish(KSJSONSerializeContext* context)
{
    return cfautoreleased(CFStringCreateWithCharactersNoCopy(NULL,
                                                             context->buffer,
                                                             (CFIndex)context->index,
                                                             NULL));
}

/** Abort the serialization process, freeing any resources.
 *
 * @param context The serialization context.
 */
static void serializeAbort(KSJSONSerializeContext* context)
{
    CFAllocatorDeallocate(NULL, context->buffer);
}

/** Add 1 character to the serialized JSON string.
 *
 * @param context The serialization context.
 *
 * @param ch The character to add.
 */
static void serializeChar(KSJSONSerializeContext* context, const unichar ch)
{
    context->buffer[context->index++] = ch;
    unlikely_if(context->index >= context->size)
    {
        serializeRealloc(context, 1);
    }
}

/** Add 2 characters to the serialized JSON string.
 *
 * @param context The serialization context.
 *
 * @param ch1 The first character to add.
 *
 * @param ch2 The second character to add.
 */
static void serialize2Chars(KSJSONSerializeContext* context,
                            const unichar ch1,
                            const unichar ch2)
{
    unlikely_if(context->index + 2 > context->size)
    {
        serializeRealloc(context, 2);
    }
    context->buffer[context->index++] = ch1;
    context->buffer[context->index++] = ch2;
}

/** Add a series of characters to the serialized JSON string.
 *
 * @param context The serialization context.
 *
 * @param chars The characters to add.
 *
 * @param length The length of the character array.
 */
static void serializeChars(KSJSONSerializeContext* context,
                           const unichar* chars,
                           unsigned int length)
{
    unlikely_if(context->index + length > context->size)
    {
        serializeRealloc(context, length);
    }
    memcpy(context->buffer+context->index, chars, length * sizeof(*chars));
    context->index += length;
}

/** Backtrack in the serialization process, erasing previously added characters.
 *
 * @param context The serialization context.
 *
 * @param numChars The number of characters to backtrack.
 */
static void serializeBacktrack(KSJSONSerializeContext* context,
                               unsigned int numChars)
{
    context->index -= numChars;
}


#pragma mark Object Serialization

/** Serialize an array.
 *
 * @param context The serialization context.
 *
 * @param array The array to serialize.
 *
 * @return true if successful.
 */
static bool serializeArray(KSJSONSerializeContext* context, CFTypeRef array)
{
    CFIndex count = CFArrayGetCount(array);
    
    unlikely_if(count == 0)
    {
        serialize2Chars(context, '[',']');
        return true;
    }
    serializeChar(context, '[');
    for(CFIndex i = 0; i < count; i++)
    {
        CFTypeRef subObject = CFArrayGetValueAtIndex(array, i);
        unlikely_if(!serializeObject(context, subObject))
        {
            return false;
        }
        serializeChar(context, ',');
    }
    serializeBacktrack(context, 1);
    serializeChar(context, ']');
    return true;
}


/** Serialize a dictionary.
 *
 * @param context The serialization context.
 *
 * @param dict The dictionary to serialize.
 *
 * @return true if successful.
 */
static bool serializeDictionary(KSJSONSerializeContext* context,
                                CFTypeRef dict)
{
    bool success = NO;
    CFIndex count = CFDictionaryGetCount(dict);
    
    unlikely_if(count == 0)
    {
        serialize2Chars(context, '{','}');
        return true;
    }
    serializeChar(context, '{');

    CFTypeRef* keys;
    CFTypeRef* values;
    
    // Try to use the stack, otherwise fall back on the heap.
    void* memory = NULL;
    const void* stackMemory[kSerialize_DictStackSize * sizeof(*keys) * 2];
    likely_if(count <= kSerialize_DictStackSize)
    {
        keys = stackMemory;
        values = keys + count;
    }
    else
    {
        memory = malloc(sizeof(*keys) * (unsigned int)count * 2);
        unlikely_if(memory == NULL)
        {
            makeError(context->error, @"Out of memory");
            return false;
        }
        keys = memory;
        values = keys + count;
    }
    
    
    CFDictionaryGetKeysAndValues(dict, keys, values);
    for(CFIndex i = 0; i < count; i++)
    {
        unlikely_if(!serializeObject(context, keys[i]))
        {
            goto done;
        }
        serializeChar(context, ':');
        unlikely_if(!serializeObject(context, values[i]))
        {
            goto done;
        }
        serializeChar(context, ',');
    }
    serializeBacktrack(context, 1);
    serializeChar(context, '}');
    
    success = YES;
done:
    unlikely_if(memory != NULL)
    {
        free(memory);
    }
    return success;
}

/** Serialize a string.
 *
 * @param context The serialization context.
 *
 * @param string The string to serialize.
 *
 * @return true if successful.
 */
static bool serializeString(KSJSONSerializeContext* context, CFTypeRef string)
{
    void* memory = NULL;
    CFIndex length = CFStringGetLength(string);
    unlikely_if(length == 0)
    {
        serialize2Chars(context, '"', '"');
        return true;
    }
    const unichar* chars = CFStringGetCharactersPtr(string);
    likely_if(chars == NULL)
    {
        likely_if(length <= kSerialize_ScratchBuffSize)
        {
            chars = context->scratchBuffer;
        }
        else
        {
            memory = malloc((unsigned int)length * sizeof(*chars));
            unlikely_if(memory == NULL)
            {
                makeError(context->error, @"Out of memory");
                return false;
            }
            chars = memory;
        }
        CFStringGetCharacters(string,
                              CFRangeMake(0, length),
                              (UniChar*)chars);
    }
    const unichar* end = chars + length;
    
    serializeChar(context, '"');
    
    const unichar* ch = chars;
    const unichar* nextEscape = ch;
    for(; nextEscape < end; nextEscape++)
    {
        unlikely_if(*nextEscape == '\\' ||
                    *nextEscape == '"' ||
                    *nextEscape < ' ')
        {
            likely_if(nextEscape > ch)
            {
                serializeChars(context, ch, (unsigned int)(nextEscape - ch));
            }
            ch = nextEscape + 1;
            switch(*nextEscape)
            {
                case '\\':
                    serialize2Chars(context, '\\', '\\');
                    break;
                case '"':
                    serialize2Chars(context, '\\', '"');
                    break;
                case '\b':
                    serialize2Chars(context, '\\', 'b');
                    break;
                case '\f':
                    serialize2Chars(context, '\\', 'f');
                    break;
                case '\n':
                    serialize2Chars(context, '\\', 'n');
                    break;
                case '\r':
                    serialize2Chars(context, '\\', 'r');
                    break;
                case '\t':
                    serialize2Chars(context, '\\', 't');
                    break;
                default:
                    makeError(context->error, @"Invalid character: 0x%02x", *nextEscape);
                    return false;
            }
        }
    }
    likely_if(nextEscape > ch)
    {
        serializeChars(context, ch, (unsigned int)(nextEscape - ch));
    }
    
    serializeChar(context, '"');
    
    unlikely_if(memory != NULL)
    {
        free(memory);
    }
    return true;
}

/** Serialize a number represented as a string of digits.
 *
 * @param context The serialization context.
 *
 * @param numberString The number to serialize.
 */
static void serializeNumberString(KSJSONSerializeContext* context,
                                  const char* numberString)
{
    const char* end = numberString + strlen(numberString);
    for(const char* ch = numberString; ch < end; ch++)
    {
        serializeChar(context, (unichar)*ch);
    }
}

/** Serialize an integer.
 *
 * @param context The serialization context.
 *
 * @param value The value to serialize.
 */
static void serializeInteger(KSJSONSerializeContext* context,
                             long long value)
{
    unlikely_if(value == 0)
    {
        serializeChar(context, '0');
        return;
    }
    
    unsigned long long uValue = (unsigned long long)value;
    if(value < 0)
    {
        serializeChar(context, '-');
        uValue = (unsigned long long)-value;
    }
    unichar buff[30];
    unichar* ptr = buff + 30;
    
    for(;uValue != 0; uValue /= 10)
    {
        ptr--;
        *ptr = (unichar)((uValue % 10) + '0');
    }
    serializeChars(context, ptr, (unsigned int)(buff + 30 - ptr));
}

/** Serialize a number.
 *
 * @param context The serialization context.
 *
 * @param number The number to serialize.
 *
 * @return true if successful.
 */
static bool serializeNumber(KSJSONSerializeContext* context,
                            CFTypeRef number)
{
    CFNumberType numberType = CFNumberGetType(number);
    char buff[100];
    switch(numberType)
    {
        case kCFNumberCharType:
        {
            char value;
            CFNumberGetValue(number, numberType, &value);
            if(value)
            {
                serializeChars(context, g_true, 4);
            }
            else
            {
                serializeChars(context, g_false, 5);
            }
            return true;
        }
        case kCFNumberFloatType:
        {
            float value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberCGFloatType:
        {
            CGFloat value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberDoubleType:
        {
            double value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberFloat32Type:
        {
            Float32 value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberFloat64Type:
        {
            Float64 value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberIntType:
        {
            int value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberNSIntegerType:
        {
            NSInteger value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberLongType:
        {
            long value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberLongLongType:
        {
            long long value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberShortType:
        {
            short value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberSInt16Type:
        {
            SInt16 value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberSInt32Type:
        {
            SInt32 value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberSInt64Type:
        {
            SInt64 value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberSInt8Type:
        {
            SInt8 value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberCFIndexType:
        {
            CFIndex value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
    }
    makeError(context->error, @"%@: Cannot serialize numeric value", number);
    return nil;
}

/** Serialize a null value.
 *
 * @param context The serialization context.
 *
 * @param object The object to serialize (unused).
 *
 * @return always true.
 */
static bool serializeNull(KSJSONSerializeContext* context, CFTypeRef object)
{
    serializeChars(context, g_null, 4);
    return true;
}

// Prototype for a serialization routine.
typedef bool (*serializeFunction)(KSJSONSerializeContext* context, CFTypeRef object);

/** The different kinds of classes we are interested in. */
typedef enum
{
    KSJSON_ClassString,
    KSJSON_ClassNumber,
    KSJSON_ClassArray,
    KSJSON_ClassDictionary,
    KSJSON_ClassNull,
    KSJSON_ClassCount,
} KSJSON_Class;

/** Cache for holding classes we've seen before. */
static Class g_classCache[KSJSON_ClassCount];

/** Pointers to functions that can serialize various classes of object. */
static const serializeFunction g_serializeFunctions[] =
{
    serializeString,
    serializeNumber,
    serializeArray,
    serializeDictionary,
    serializeNull,
};

/** Serialize an object.
 *
 * @param context The serialization context.
 *
 * @param objectRef The object to serialize.
 *
 * @return true if successful.
 */
static bool serializeObject(KSJSONSerializeContext* context, CFTypeRef objectRef)
{
    id object = (__bridge id) objectRef;

    // Check the cache first.
    Class cls = object_getClass(object);
    for(KSJSON_Class i = 0; i < KSJSON_ClassCount; i++)
    {
        unlikely_if(g_classCache[i] == cls)
        {
            return g_serializeFunctions[i](context, objectRef);
        }
    }
    
    // Failing that, look it up the long way and cache the class.
    KSJSON_Class classType = KSJSON_ClassCount;
    if([object isKindOfClass:[NSString class]])
    {
        classType = KSJSON_ClassString;
    }
    else if([object isKindOfClass:[NSNumber class]])
    {
        classType = KSJSON_ClassNumber;
    }
    else if([object isKindOfClass:[NSArray class]])
    {
        classType = KSJSON_ClassArray;
    }
    else if([object isKindOfClass:[NSDictionary class]])
    {
        classType = KSJSON_ClassDictionary;
    }
    else if([object isKindOfClass:[NSNull class]])
    {
        classType = KSJSON_ClassNull;
    }
    else
    {
        makeError(context->error,
                  @"Cannot serialize object of type %@", [object class]);
        return false;
    }
    
    g_classCache[classType] = cls;
    return g_serializeFunctions[classType](context, objectRef);
}


#pragma mark -
#pragma mark Objective-C Implementation
#pragma mark -

@implementation KSJSON

/** Serialize an object.
 *
 * @param object The object to serialize.
 *
 * @param error Place to store any error that occurs (nil = ignore).
 *
 * @return The serialized object or nil if an error occurred.
 */
+ (NSString*) serializeObject:(id) object error:(NSError**) error
{
    if(error != nil)
    {
        *error = nil;
    }
    unlikely_if(![object isKindOfClass:[NSArray class]] &&
                ![object isKindOfClass:[NSDictionary class]])
    {
        makeError(error, @"Top level object must be an array or dictionary.");
        return nil;
    }
    KSJSONSerializeContext context;
    context.error = error;
    serializeInit(&context);
    
    CFTypeRef objectRef = (__bridge CFTypeRef)object;
    
    likely_if(serializeObject(&context, objectRef))
    {
        return serializeFinish(&context);
    }
    
    serializeAbort(&context);
    return nil;
}

/** Deserialize a JSON string.
 *
 * @param jsonString The string to deserialize.
 *
 * @param error Place to store any error that occurs (nil = ignore).
 *
 * @return The deserialized object or nil if an error occurred.
 */
+ (id) deserializeString:(NSString*) jsonString error:(NSError**) error
{
    if(error != nil)
    {
        *error = nil;
    }
    CFStringRef stringRef = (__bridge CFStringRef) jsonString;
    CFIndex length = CFStringGetLength(stringRef);
    unichar* start = malloc((unsigned int)length * sizeof(*start));
    unlikely_if(start == NULL)
    {
        makeError(error, @"Out of memory");
        return nil;
    }
    CFStringGetCharacters(stringRef, CFRangeMake(0, length), (UniChar*)start);
    unichar* end = start + length;
    KSJSONDeserializeContext context =
    {
        start,
        end,
        error
    };
    
    id result = cfautoreleased(deserializeJSON(&context));
    unlikely_if(error != nil && *error != nil)
    {
        NSString* desc = [(*error).userInfo valueForKey:NSLocalizedDescriptionKey];
        desc = [desc stringByAppendingFormat:@" (at offset %d)", context.pos - start];
        *error = [NSError errorWithDomain:@"KSJSON"
                                     code:1
                                 userInfo:[NSDictionary dictionaryWithObject:desc
                                                                      forKey:NSLocalizedDescriptionKey]];
    }
    
    free(start);
    return result;
}

@end
