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
#define kScratchBuffSize 1024

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

/** Check for an error and return with the specified value (or none) if
 * an error is detected.
 */
#define on_error_return(...) \
unlikely_if(*context->error != nil) \
{ \
    return __VA_ARGS__; \
}

/** Check for an error and goto the specified label if an error is detected.
 */
#define on_error_goto(X) \
unlikely_if(*context->error != nil) \
{ \
    goto X; \
}



#pragma mark Error Handling

/** Make an error object with the specified message.
 *
 * @param error Pointer to a location to store the error object.
 *
 * @param fmt The message to fill the error object with.
 */
static void makeError(NSError** restrict error, NSString* fmt, ...)
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



#pragma mark Resizable Buffer

/** A buffer that can resize itself. */
typedef struct
{
    /** The size of the buffer. */
    size_t size;
    /** The number of bytes considered reserved for future use. */
    size_t reserved;
    /** Allocated memory */
    unsigned char* bytes;
    /** The first unused byte in the buffer. */
    unsigned char* restrict pos;
} KSJSONResizableBuffer;

/** Initialize a resizable buffer.
 *
 * @param buffer The buffer to initialize.
 *
 * @size The number of bytes to allocate.
 *
 * @param error Where to store any errors should they occur.
 */
static void resizableBufferInit(KSJSONResizableBuffer* restrict buffer,
                                size_t size,
                                NSError** restrict error)
{
    buffer->size = size;
    buffer->reserved = 0;
    buffer->bytes = CFAllocatorAllocate(NULL,
                                        (CFIndex)(sizeof(buffer->bytes[0]) * buffer->size),
                                        0);
    buffer->pos = buffer->bytes;
    unlikely_if(buffer->bytes == NULL)
    {
        makeError(error, @"Out of memory");
    }
}

/** Set the amount of reserved space for a buffer.
 *
 * @param buffer The buffer.
 *
 * @param size The new reserved size.
 *
 * @param error Where to store any errors should they occur.
 */
static void resizableBufferSetReservedSize(KSJSONResizableBuffer* restrict buffer,
                                           size_t size,
                                           NSError** restrict error)
{
    buffer->reserved = size;
    unlikely_if(buffer->reserved > buffer->size)
    {
        // Keep doubling the size until there's enough room.
        while(buffer->reserved > buffer->size)
        {
            buffer->size <<= 1;
        }
        unsigned char* newBytes = CFAllocatorReallocate(NULL,
                                                        buffer->bytes,
                                                        (CFIndex)(sizeof(buffer->bytes[0]) * buffer->size),
                                                        0);
        unlikely_if(newBytes == NULL)
        {
            makeError(error, @"Out of memory");
            return;
        }
        buffer->pos = newBytes + (buffer->pos - buffer->bytes);
        buffer->bytes = newBytes;
    }
}

/** Reserve additional space in a buffer.
 *
 * @param buffer The buffer.
 *
 * @param size The number of additional bytes to reserve.
 *
 * @param error Where to store any errors should they occur.
 */
static inline void resizableBufferReserve(KSJSONResizableBuffer* restrict buffer,
                                          size_t size,
                                          NSError** restrict error)
{
    resizableBufferSetReservedSize(buffer, buffer->reserved + size, error);
}

/** Reallocate a buffer to its optimal size (enough to hold data up to the
 * current position in the buffer.
 *
 * @param buffer The buffer.
 */
static void resizableBufferResizeOptimal(KSJSONResizableBuffer* restrict buffer)
{
    likely_if(buffer->bytes + buffer->size > buffer->pos)
    {
        buffer->reserved = buffer->size = (size_t)(buffer->pos - buffer->bytes);
        buffer->bytes = CFAllocatorReallocate(NULL,
                                              buffer->bytes,
                                              (CFIndex)(sizeof(buffer->bytes[0]) * buffer->size),
                                              0);
        buffer->pos = buffer->bytes + buffer->size;
    }
}

/** Free all resources used by this buffer.
 *
 * @param buffer The buffer.
 */
static void resizableBufferFree(KSJSONResizableBuffer* restrict buffer)
{
    CFAllocatorDeallocate(NULL, buffer->bytes);
}



#pragma mark Context & Helpers

/** Deserializing contextual information.
 */
typedef struct
{
    /** The beginning of the JSON string. */
    const unsigned char* start;
    /** Current position in the JSON string. */
    const unsigned char* restrict pos;
    /** End of the JSON string. */
    const unsigned char* end;
    /** Any error that has occurred. */
    __autoreleasing NSError** restrict error;
    KSJSONResizableBuffer scratch;
} KSJSONDeserializeContext;


// Forward reference.
static CFTypeRef deserializeElement(KSJSONDeserializeContext* restrict context);

/** Lookup table for values that require escaping.
 */
static bool g_escapeValues[256] = {false};


/** Lookup table for converting hex values to integers.
 * 0x77 is used to mark invalid characters.
 */
static unsigned char g_hexConversion[] =
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
 * @param error Where to store any errors should they occur.
 *
 * @return The number of bytes used for the UTF-8 representation.
 */
static unsigned int parseUnicodeSequence(KSJSONDeserializeContext* restrict context,
                                         const unsigned char* restrict src,
                                         unsigned char* restrict dst)
{
    unsigned int accum = 0;
    unsigned int next;

    next = (unsigned int)(*src++ - '0');
    unlikely_if(next >= g_hexConversionEnd || g_hexConversion[next] == 0x77)
    {
        makeError(context->error, @"Invalid unicode sequence");
        return 0;
    }
    accum = (accum << 4) + g_hexConversion[next];
    
    next = (unsigned int)(*src++ - '0');
    unlikely_if(next >= g_hexConversionEnd || g_hexConversion[next] == 0x77)
    {
        makeError(context->error, @"Invalid unicode sequence");
        return 0;
    }
    accum = (accum << 4) + g_hexConversion[next];
    
    next = (unsigned int)(*src++ - '0');
    unlikely_if(next >= g_hexConversionEnd || g_hexConversion[next] == 0x77)
    {
        makeError(context->error, @"Invalid unicode sequence");
        return 0;
    }
    accum = (accum << 4) + g_hexConversion[next];
    
    next = (unsigned int)(*src++ - '0');
    unlikely_if(next >= g_hexConversionEnd || g_hexConversion[next] == 0x77)
    {
        makeError(context->error, @"Invalid unicode sequence");
        return 0;
    }
    accum = (accum << 4) + g_hexConversion[next];

    if(accum <= 0x7f)
    {
        *dst = (unsigned char)accum;
        return 1;
    }
    if(accum <= 0x7ff)
    {
        *dst++ = (unsigned char)(0xc0 | (accum>>6));
        *dst = (unsigned char)(0x80 | (accum&0x3f));
        return 2;
    }
    *dst++ = (unsigned char)(0xe0 | (accum>>12));
    *dst++ = (unsigned char)(0x80 | ((accum>>6)&0x3f));
    *dst = (unsigned char)(0x80 | (accum&0x3f));
    return 3;
}

/** Initialize a deserialization context.
 *
 * @param context The context.
 *
 * @param jsonData The data to deserialize.
 */
static void deserializeInit(KSJSONDeserializeContext* restrict context, NSData* jsonData)
{
    unlikely_if(jsonData == nil)
    {
        makeError(context->error, @"data is nil");
        return;
    }
    
    CFDataRef dataRef = (__bridge CFDataRef) jsonData;
    const unsigned char* start = (const unsigned char*)CFDataGetBytePtr(dataRef);    
    context->pos = start;
    context->end = start + CFDataGetLength(dataRef);
    
    resizableBufferInit(&context->scratch, kScratchBuffSize, context->error);
}

/** Deserialize a string.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFStringRef deserializeString(KSJSONDeserializeContext* restrict context)
{
    unlikely_if(*context->pos != '"')
    {
        makeError(context->error, @"Expected a string");
        return nil;
    }
    unlikely_if(context->pos[1] == '"')
    {
        // Empty string
        context->pos += 2;
        return CFStringCreateWithCString(NULL,
                                         "",
                                         kCFStringEncodingUTF8);
    }
    context->pos++;
    
    resizableBufferSetReservedSize(&context->scratch, 0, context->error);
    context->scratch.pos = context->scratch.bytes;
    
    // Look for a closing quote
    for(;context->pos < context->end; context->pos++)
    {
        resizableBufferReserve(&context->scratch, 1, context->error);
        on_error_return(nil);
        likely_if(*context->pos != '\\')
        {
            // Normal char
            unlikely_if(*context->pos == '"')
            {
                break;
            }
            *context->scratch.pos++ = *context->pos;
        }
        else
        {
            // Escaped char
            context->pos++;
            switch(*context->pos)
            {
                case '\\':
                case '/':
                case '"':
                    *context->scratch.pos++ = *context->pos;
                    break;
                case 'b':
                    *context->scratch.pos++ = '\b';
                    break;
                case 'f':
                    *context->scratch.pos++ = '\f';
                    break;
                case 'n':
                    *context->scratch.pos++ = '\n';
                    break;
                case 'r':
                    *context->scratch.pos++ = '\r';
                    break;
                case 't':
                    *context->scratch.pos++ = '\t';
                    break;
                case 'u':
                {
                    context->pos++;
                    unlikely_if(context->pos > context->end - 4)
                    {
                        makeError(context->error, @"Unterminated escape sequence");
                        return nil;
                    }
                    resizableBufferReserve(&context->scratch, 3, context->error);
                    on_error_return(nil);
                    context->scratch.pos += parseUnicodeSequence(context, context->pos, context->scratch.pos);
                    on_error_return(nil);
                    context->pos += 3;
                    break;
                }
                default:
                    makeError(context->error, @"Invalid escape sequence");
                    return nil;
            }
        }
    }

    unlikely_if(context->pos >= context->end)
    {
        makeError(context->error, @"Unterminated string");
        return nil;
    }

    context->pos++;
    return CFStringCreateWithBytes(NULL,
                                   context->scratch.bytes,
                                   context->scratch.pos - context->scratch.bytes,
                                   kCFStringEncodingUTF8,
                                   NO);
}


#pragma mark Number Deserialization

/** Check if a character is valid for representing part of a floating point
 * number.
 *
 * @param ch The character to test.
 *
 * @return true if the character is valid for floating point.
 */
static bool isFPChar(unsigned char ch)
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
static CFNumberRef deserializeNumber(KSJSONDeserializeContext* restrict context)
{
    const unsigned char* start = context->pos;
    
    // First, try to do a simple integer conversion.
    long long accum = 0;
    long long sign = *context->pos == '-' ? -1 : 1;
    if(sign == -1)
    {
        context->pos++;
    }
    
    for(;context->pos < context->end && isdigit(*context->pos); context->pos++)
    {
        accum = accum * 10 + (*context->pos - '0');
        unlikely_if(accum < 0)
        {
            // Overflow
            break;
        }
    }
    
    if(!isFPChar(*context->pos))
    {
        accum *= sign;
        return CFNumberCreate(NULL, kCFNumberLongLongType, &accum);
    }

    // Fall back on strtod.
    const unsigned char* end;
    double result = strtod((const char*)start, (char**)&end);
    context->pos = end;
    return CFNumberCreate(NULL, kCFNumberDoubleType, &result);
}


#pragma mark Other Deserialization

/** Deserialize "false".
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFNumberRef deserializeFalse(KSJSONDeserializeContext* restrict context)
{
    unlikely_if(context->end - context->pos < 5)
    {
        makeError(context->error, @"Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(context->pos[1] == 'a' &&
                  context->pos[2] == 'l' &&
                  context->pos[3] == 's' &&
                  context->pos[4] == 'e'))
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
static CFNumberRef deserializeTrue(KSJSONDeserializeContext* restrict context)
{
    unlikely_if(context->end - context->pos < 4)
    {
        makeError(context->error, @"Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(context->pos[1] == 'r' &&
                  context->pos[2] == 'u' &&
                  context->pos[3] == 'e'))
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
static CFNullRef deserializeNull(KSJSONDeserializeContext* restrict context)
{
    unlikely_if(context->end - context->pos < 4)
    {
        makeError(context->error, @"Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(context->pos[1] == 'u' &&
                  context->pos[2] == 'l' &&
                  context->pos[3] == 'l'))
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
    CFTypeRef* restrict values;
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
static void arrayInit(Array* restrict array)
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
 * @param error Holds any errors that occur.
 *
 * @return true if the object was successfully added.
 */
static void arrayAddValue(KSJSONDeserializeContext* restrict context,
                          Array* restrict array,
                          CFTypeRef value)
{
    // Check if we need to resize the array.
    unlikely_if(array->index >= array->length)
    {
        array->length <<= 1;
        if(array->onStack)
        {
            // Switching from stack to heap.
            array->values = malloc(array->length * sizeof(*array->values));
            unlikely_if(array->values == NULL)
            {
                makeError(context->error, @"Out of memory");
                return;
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
                makeError(context->error, @"Out of memory");
                return;
            }
        }
    }
    array->values[array->index] = value;
    array->index++;
}

/** Free an array. All objects will be released.
 *
 * @param array The array to free.
 */
static void arrayFree(Array* restrict array)
{
    // Release everything in the array first.
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
static CFArrayRef deserializeArray(KSJSONDeserializeContext* restrict context)
{
    CFTypeRef result = NULL;
    context->pos++;
    Array array;
    arrayInit(&array);
    
    while(context->pos < context->end)
    {
        skipWhitespace(context->pos, context->end);
        unlikely_if(*context->pos == ARRAY_END)
        {
            context->pos++;
            result = CFArrayCreate(NULL,
                                   array.values,
                                   (CFIndex)array.index,
                                   &kCFTypeArrayCallBacks);
            unlikely_if(result == NULL)
            {
                makeError(context->error, @"Could not create new array");
            }
            goto done;
        }
        CFTypeRef element = deserializeElement(context);
        on_error_goto(done);
        arrayAddValue(context, &array, element);
        on_error_goto(done);
        skipWhitespace(context->pos, context->end);
        likely_if(*context->pos == ELEMENT_SEPARATOR)
        {
            context->pos++;
        }
    }
    makeError(context->error, @"Unterminated array");

done:
    arrayFree(&array);
    return result;
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
    CFTypeRef* restrict keys;
    /** Heap storage for values when the array is bigger. */
    CFTypeRef* restrict values;
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
static void dictInit(Dictionary* restrict dict)
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
 * @param error Holds any errors that occur.
 *
 * @return true if the pair was successfully added.
 */
static void dictAddKeyAndValue(KSJSONDeserializeContext* restrict context,
                               Dictionary* restrict dict,
                               CFStringRef key,
                               CFTypeRef value)
{
    unlikely_if(dict->index >= dict->length)
    {
        dict->length <<= 1;
        if(dict->onStack)
        {
            // Switching from stack to heap.
            dict->keys = malloc(dict->length * sizeof(*dict->keys));
            dict->values = malloc(dict->length * sizeof(*dict->values));
            unlikely_if(dict->keys == NULL || dict->values == NULL)
            {
                if(dict->keys != NULL)
                {
                    free(dict->keys);
                }
                makeError(context->error, @"Out of memory");
                return;
            }
            dict->onStack = false;
            memcpy(dict->keys, dict->keysOnStack, dict->length * sizeof(*dict->keys));
            memcpy(dict->values, dict->valuesOnStack, dict->length * sizeof(*dict->values));
        }
        else
        {
            // Already on the heap, so reallocate.
            CFTypeRef* newKeys = realloc(dict->keys, dict->length * sizeof(*dict->keys));
            CFTypeRef* newValues = realloc(dict->values, dict->length * sizeof(*dict->values));
            unlikely_if(dict->keys == NULL || dict->values == NULL)
            {
                // Make sure allocated data is properly pointed to for cleanup.
                if(newKeys != NULL)
                {
                    dict->keys = newKeys;
                }
                makeError(context->error, @"Out of memory");
                return;
            }
            dict->keys = newKeys;
            dict->values = newValues;
        }
    }
    dict->keys[dict->index] = key;
    dict->values[dict->index] = value;
    dict->index++;
}

/** Free a dictionary. All keys and objects will be released.
 *
 * @param dict The dictionary to free.
 */
static void dictFree(Dictionary* restrict dict)
{
    // Release keys and values first.
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
static CFDictionaryRef deserializeDictionary(KSJSONDeserializeContext* restrict context)
{
    CFTypeRef result = NULL;
    context->pos++;
    Dictionary dict;
    dictInit(&dict);
    
    while(context->pos < context->end)
    {
        skipWhitespace(context->pos, context->end);
        unlikely_if(*context->pos == DICTIONARY_END)
        {
            context->pos++;
            result = CFDictionaryCreate(NULL,
                                        dict.keys,
                                        dict.values,
                                        (CFIndex)dict.index,
                                        &kCFTypeDictionaryKeyCallBacks,
                                        &kCFTypeDictionaryValueCallBacks);
            unlikely_if(result == NULL)
            {
                makeError(context->error, @"Could not create new dictionary");
            }
            goto done;
        }
        CFStringRef name = deserializeString(context);
        on_error_goto(done);
        skipWhitespace(context->pos, context->end);
        unlikely_if(*context->pos != NAME_SEPARATOR)
        {
            makeError(context->error, @"Expected name separator");
            goto done;
        }
        context->pos++;
        CFTypeRef element = deserializeElement(context);
        on_error_goto(done);
        dictAddKeyAndValue(context, &dict, name, element);
        on_error_goto(done);
        skipWhitespace(context->pos, context->end);
        likely_if(*context->pos == ELEMENT_SEPARATOR)
        {
            context->pos++;
        }
    }
    
    makeError(context->error, @"Unterminated object");

done:
    dictFree(&dict);
    return result;
}


#pragma mark Top Level Deserialization

/** Deserialize an unknown element.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized value, or nil if an error occurred.
 */
static CFTypeRef deserializeElement(KSJSONDeserializeContext* restrict context)
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
        default:
            makeError(context->error, @"Unexpected character: %c", *context->pos);
            return nil;
    }
}

/** Begin the JSON deserialization process.
 *
 * @param context The deserialization context.
 *
 * @return The deserialized container, or nil if an error occurred.
 */
static CFTypeRef deserializeJSON(KSJSONDeserializeContext* restrict context)
{
    skipWhitespace(context->pos, context->end);
    switch(*context->pos)
    {
        case ARRAY_BEGIN:
            return deserializeArray(context);
        case DICTIONARY_BEGIN:
            return deserializeDictionary(context);
        default:
            makeError(context->error, @"Unexpected character: %c", *context->pos);
            return nil;
    }
}


#pragma mark -
#pragma mark Serialization
#pragma mark -


#pragma mark Serialization Helpers

/** Contextual information while serializing. */
typedef struct
{
    /** Buffer for the resulting string. */
    KSJSONResizableBuffer buffer;
    /** Scratch buffer for some operations. */
    KSJSONResizableBuffer scratch;
    /** Any error that has occurred. */
    __autoreleasing NSError** error;
} KSJSONSerializeContext;

static unsigned char g_false[] = {'f','a','l','s','e'};
static unsigned char g_true[] = {'t','r','u','e'};
static unsigned char g_null[] = {'n','u','l','l'};

// Forward declaration
static void serializeObject(KSJSONSerializeContext* restrict context, CFTypeRef object);


/** Initialize a serialization context.
 *
 * @param context The context to initialize.
 *
 * @return true if successful.
 */
static void serializeInit(KSJSONSerializeContext* restrict context)
{
    resizableBufferInit(&context->buffer, kSerialize_InitialBuffSize, context->error);
    resizableBufferInit(&context->scratch, kScratchBuffSize, context->error);
}

/** Finish the serialization process, returning the serializd JSON string.
 *
 * @param context The serialization context.
 *
 * @return The JSON string.
 */
static NSData* serializeFinish(KSJSONSerializeContext* restrict context)
{
    resizableBufferFree(&context->scratch);
    resizableBufferResizeOptimal(&context->buffer);
    return cfautoreleased(CFDataCreateWithBytesNoCopy(NULL,
                                                      context->buffer.bytes,
                                                      context->buffer.pos - context->buffer.bytes,
                                                      NULL));
}

/** Abort the serialization process, freeing any resources.
 *
 * @param context The serialization context.
 */
static void serializeAbort(KSJSONSerializeContext* restrict context)
{
    resizableBufferFree(&context->buffer);
    resizableBufferFree(&context->scratch);
}

#define serializeReserve(CONTEXT, NUM_BYTES) \
resizableBufferReserve(&CONTEXT->buffer, NUM_BYTES, CONTEXT->error)

/** Add 1 character to the serialized JSON string.
 *
 * @param context The serialization context.
 *
 * @param ch The character to add.
 */
#define serializeChar(CONTEXT, CH) \
*CONTEXT->buffer.pos++ = CH

/** Add 2 characters to the serialized JSON string.
 *
 * @param context The serialization context.
 *
 * @param ch1 The first character to add.
 *
 * @param ch2 The second character to add.
 */
#define serialize2Chars(CONTEXT, CH1, CH2) \
*CONTEXT->buffer.pos++ = CH1; \
*CONTEXT->buffer.pos++ = CH2

/** Add a series of characters to the serialized JSON string.
 *
 * @param context The serialization context.
 *
 * @param chars The characters to add.
 *
 * @param length The length of the character array.
 */
#define serializeChars(CONTEXT, CHARS, LENGTH) \
{ \
    unsigned int xLength = (unsigned int)(LENGTH); \
    memcpy(CONTEXT->buffer.pos, CHARS, xLength); \
    CONTEXT->buffer.pos += xLength; \
}

/** Backtrack in the serialization process, erasing previously added characters.
 *
 * @param context The serialization context.
 *
 * @param numChars The number of characters to backtrack.
 */
#define serializeBacktrack(CONTEXT, NUM_CHARS) \
CONTEXT->buffer.pos -= NUM_CHARS


#pragma mark Object Serialization

/** Serialize an array.
 *
 * @param context The serialization context.
 *
 * @param array The array to serialize.
 *
 * @return true if successful.
 */
static void serializeArray(KSJSONSerializeContext* restrict context,
                           CFTypeRef array)
{
    CFIndex count = CFArrayGetCount(array);
    
    // Empty array.
    unlikely_if(count == 0)
    {
        serializeReserve(context, 2);
        on_error_return()
        serialize2Chars(context, '[',']');
        return;
    }

    serializeReserve(context, (unsigned int)count + 2);
    on_error_return()
    serializeChar(context, '[');
    for(CFIndex i = 0; i < count; i++)
    {
        serializeObject(context, CFArrayGetValueAtIndex(array, i));
        on_error_return()
        serializeChar(context, ',');
    }
    serializeBacktrack(context, 1);
    serializeChar(context, ']');
}


/** Serialize a dictionary.
 *
 * @param context The serialization context.
 *
 * @param dict The dictionary to serialize.
 *
 * @return true if successful.
 */
static void serializeDictionary(KSJSONSerializeContext* restrict context,
                                CFTypeRef dict)
{
    void* memory = NULL;

    CFIndex count = CFDictionaryGetCount(dict);
    
    // Empty dictionary.
    unlikely_if(count == 0)
    {
        serializeReserve(context, 2);
        on_error_return();
        serialize2Chars(context, '{','}');
        return;
    }
    
    serializeReserve(context, (unsigned int)count * 2 + 2);
    on_error_return();
    serializeChar(context, '{');
    
    CFTypeRef* keys;
    CFTypeRef* values;
    
    // Try to use the stack, otherwise fall back on the heap.
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
            return;
        }
        keys = memory;
        values = keys + count;
    }
    
    CFDictionaryGetKeysAndValues(dict, keys, values);
    for(CFIndex i = 0; i < count; i++)
    {
        serializeObject(context, keys[i]);
        on_error_goto(done);
        serializeChar(context, ':');
        serializeObject(context, values[i]);
        on_error_goto(done);
        serializeChar(context, ',');
    }
    serializeBacktrack(context, 1);
    serializeChar(context, '}');

done:
    unlikely_if(memory != NULL)
    {
        free(memory);
    }
}

/** Serialize a string.
 *
 * @param context The serialization context.
 *
 * @param string The string to serialize.
 *
 * @return true if successful.
 */
static void serializeString(KSJSONSerializeContext* restrict context,
                            CFTypeRef string)
{
    CFIndex length = CFStringGetLength(string);

    // Empty string
    unlikely_if(length == 0)
    {
        serializeReserve(context, 2);
        on_error_return();
        serialize2Chars(context, '"', '"');
        return;
    }

    // max 3 bytes per char. Not sure if we really need to support 4.
    CFIndex byteLength = length * 3 + 1;
    resizableBufferSetReservedSize(&context->scratch,
                                   (size_t)byteLength,
                                   context->error);
    CFStringGetBytes(string,
                     CFRangeMake(0, length),
                     kCFStringEncodingUTF8,
                     '?',
                     NO,
                     (UInt8*)context->scratch.bytes,
                     byteLength,
                     &byteLength);
    
    serializeReserve(context, (unsigned int)byteLength + 2);
    on_error_return();
    serializeChar(context, '"');
    
    context->scratch.pos = context->scratch.bytes;
    const unsigned char* end = context->scratch.pos + byteLength;
    
    for(; context->scratch.pos < end; context->scratch.pos++)
    {
        likely_if(!g_escapeValues[*context->scratch.pos])
        {
            serializeChar(context, *context->scratch.pos);
        }
        else
        {
            serializeReserve(context, 1);
            on_error_return();
            switch(*context->scratch.pos)
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
                    makeError(context->error, @"Invalid character: 0x%02x", *context->scratch.pos);
                    return;
            }
        }
    }

    serializeChar(context, '"');
}

/** Serialize a number represented as a string of digits.
 *
 * @param context The serialization context.
 *
 * @param numberString The number to serialize.
 */
static void serializeNumberString(KSJSONSerializeContext* restrict context,
                                  const char* restrict numberString)
{
    size_t length = strlen(numberString);
    serializeReserve(context, length);
    on_error_return();
    serializeChars(context, numberString, length);
}

/** Serialize an integer.
 *
 * @param context The serialization context.
 *
 * @param value The value to serialize.
 */
static void serializeInteger(KSJSONSerializeContext* restrict context,
                             long long value)
{
    unlikely_if(value == 0)
    {
        serializeReserve(context, 1);
        on_error_return();
        serializeChar(context, '0');
        return;
    }
    
    unsigned long long uValue = (unsigned long long)value;
    if(value < 0)
    {
        serializeReserve(context, 1);
        on_error_return();
        serializeChar(context, '-');
        uValue = (unsigned long long)-value;
    }
    unsigned char buff[30];
    unsigned char* ptr = buff + 30;
    
    for(;uValue != 0; uValue /= 10)
    {
        ptr--;
        *ptr = (unsigned char)((uValue % 10) + '0');
    }
    serializeReserve(context, (unsigned int)(buff + 30 - ptr));
    on_error_return();
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
static void serializeNumber(KSJSONSerializeContext* restrict context,
                            CFTypeRef number)
{
    CFNumberType numberType = CFNumberGetType(number);
    char buff[100];
    switch(numberType)
    {
        case kCFNumberSInt32Type:
        {
            SInt32 value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        case kCFNumberSInt64Type:
        {
            SInt64 value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        case kCFNumberFloat32Type:
        {
            Float32 value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return;
        }
        case kCFNumberFloat64Type:
        {
            Float64 value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return;
        }
        case kCFNumberCharType:
        {
            char value;
            CFNumberGetValue(number, numberType, &value);
            if(value)
            {
                serializeReserve(context, 4);
                on_error_return();
                serializeChars(context, g_true, 4);
            }
            else
            {
                serializeReserve(context, 5);
                on_error_return();
                serializeChars(context, g_false, 5);
            }
            return;
        }
        case kCFNumberSInt8Type:
        {
            SInt8 value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        case kCFNumberSInt16Type:
        {
            SInt16 value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
            
        // I could not coax NSNumber or CFNumber to use these types
        case kCFNumberFloatType:
        {
            float value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return;
        }
        case kCFNumberCGFloatType:
        {
            CGFloat value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return;
        }
        case kCFNumberDoubleType:
        {
            double value;
            CFNumberGetValue(number, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return;
        }
        case kCFNumberIntType:
        {
            int value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        case kCFNumberNSIntegerType:
        {
            NSInteger value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        case kCFNumberLongType:
        {
            long value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        case kCFNumberLongLongType:
        {
            long long value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        case kCFNumberShortType:
        {
            short value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        case kCFNumberCFIndexType:
        {
            CFIndex value;
            CFNumberGetValue(number, numberType, &value);
            serializeInteger(context, value);
            return;
        }
        default:
            makeError(context->error,
                      @"%@: Cannot serialize numeric value", number);
    }
}

/** Serialize a null value.
 *
 * @param context The serialization context.
 *
 * @param object The object to serialize (unused).
 *
 * @return always true.
 */
static void serializeNull(KSJSONSerializeContext* restrict context,
                          CFTypeRef object)
{
#pragma unused(object)
    serializeReserve(context, 4);
    on_error_return();
    serializeChars(context, g_null, 4);
}

// Prototype for a serialization routine.
typedef void (*serializeFunction)(KSJSONSerializeContext* restrict context,
                                  CFTypeRef object);

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
static void serializeObject(KSJSONSerializeContext* restrict context,
                            CFTypeRef objectRef)
{
    id object = (__bridge id) objectRef;
    
    // Check the cache first.
    Class cls = object_getClass(object);
    for(KSJSON_Class i = 0; i < KSJSON_ClassCount; i++)
    {
        unlikely_if(g_classCache[i] == cls)
        {
            g_serializeFunctions[i](context, objectRef);
            return;
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
        return;
    }
    
    g_classCache[classType] = cls;
    g_serializeFunctions[classType](context, objectRef);
}

#pragma mark -
#pragma mark Objective-C Implementation
#pragma mark -

@implementation KSJSON

+ (void) initialize
{
    for(unsigned int i = 0; i < ' '; i++)
    {
        g_escapeValues[i] = true;
    }
    g_escapeValues['\\'] = true;
    g_escapeValues['"'] = true;
}

/** Serialize an object.
 *
 * @param object The object to serialize.
 *
 * @param error Place to store any error that occurs (nil = ignore).
 *
 * @return The serialized object or nil if an error occurred.
 */
+ (NSData*) serializeObject:(id) object error:(NSError**) error
{
    __autoreleasing NSError* fakeError;
    if(error == nil)
    {
        error = &fakeError;
    }
    KSJSONSerializeContext concreteContext;
    KSJSONSerializeContext* context = &concreteContext;
    context->error = error;
    *context->error = nil;

    unlikely_if(object == nil)
    {
        makeError(context->error, @"object is nil");
        return nil;
    }

    unlikely_if(![object isKindOfClass:[NSArray class]] &&
                ![object isKindOfClass:[NSDictionary class]])
    {
        makeError(context->error, @"Top level object must be an array or dictionary.");
        return nil;
    }
    
    serializeInit(context);
    on_error_goto(failed);
    CFTypeRef objectRef = (__bridge CFTypeRef)object;
    serializeObject(context, objectRef);
    on_error_goto(failed);
    return serializeFinish(context);

failed:
    serializeAbort(context);
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
+ (id) deserializeData:(NSData*) jsonData error:(NSError**) error
{
    __autoreleasing NSError* fakeError;
    if(error == nil)
    {
        error = &fakeError;
    }
    KSJSONDeserializeContext concreteContext;
    KSJSONDeserializeContext* context = &concreteContext;
    context->error = error;
    *context->error = nil;
    
    deserializeInit(context, jsonData);
    on_error_return(nil);

    id result = cfautoreleased(deserializeJSON(context));
    
    unlikely_if(*(context->error) != NULL)
    {
        NSString* desc = [(*error).userInfo valueForKey:NSLocalizedDescriptionKey];
        makeError(context->error, @"%@ (at offset %d)",
                  desc, context->pos - context->start);
        return nil;
    }
    
    return result;
}

@end
