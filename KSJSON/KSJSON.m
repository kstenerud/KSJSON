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

#define skipWhitespace(CH,END) for(;(CH) < (END) && isspace(*(CH));(CH)++) {}

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

#define likely_if(x) if(__builtin_expect(x,1))
#define unlikely_if(x) if(__builtin_expect(x,0))

#if __has_feature(objc_arc)
    #define autoreleased(X) (X)
    #define cfautoreleased(X) ((__bridge_transfer id)(X))
#else
    #define autoreleased(X) [(X) autorelease]
    #define cfautoreleased(X) [((__bridge_transfer id)(X)) autorelease]
#endif


typedef struct
{
    unichar** pos;
    unichar* end;
    __autoreleasing NSError** error;
} KSJSONDeserializeContext;



static id deserializeJSON(KSJSONDeserializeContext* context);
static id deserializeElement(KSJSONDeserializeContext* context);
static id deserializeArray(KSJSONDeserializeContext* context);
static id deserializeDictionary(KSJSONDeserializeContext* context);
static NSString* deserializeString(KSJSONDeserializeContext* context);

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
static unsigned int g_hexConversionEnd = sizeof(g_hexConversion) /
sizeof(*g_hexConversion);

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

static NSString* deserializeString(KSJSONDeserializeContext* context)
{
    unichar* ch = *context->pos;
    unlikely_if(*ch != '"')
    {
        makeError(context->error, @"Expected a string");
        return nil;
    }
    unlikely_if(ch[1] == '"')
    {
        *context->pos = ch + 2;
        return cfautoreleased(CFStringCreateWithCString(NULL,
                                                        "",
                                                        kCFStringEncodingUTF8));
    }
    ch++;
    unichar* start = ch;
    unichar* pStr = start;
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
    
    *context->pos = ch + 1;
    return cfautoreleased(CFStringCreateWithCharacters(NULL,
                                                       start,
                                                       (CFIndex)(pStr - start)));
}



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

static NSNumber* deserializeNumber(KSJSONDeserializeContext* context)
{
    unichar* start = *context->pos;
    unichar* ch = start;
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
        *context->pos = ch;
        return cfautoreleased(CFNumberCreate(NULL, kCFNumberLongLongType, &accum));
    }
    
    for(;ch < context->end && isFPChar(*ch); ch++)
    {
    }
    
    *context->pos = ch;
    
    NSString* string = cfautoreleased(CFStringCreateWithCharacters(NULL, start, ch - start));
    return [NSDecimalNumber decimalNumberWithString:string];
}

static NSNumber* deserializeFalse(KSJSONDeserializeContext* context)
{
    const unichar* ch = *context->pos;
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
    *context->pos += 5;
    char no = 0;
    return cfautoreleased(CFNumberCreate(NULL, kCFNumberCharType, &no));
}

static NSNumber* deserializeTrue(KSJSONDeserializeContext* context)
{
    const unichar* ch = *context->pos;
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
    *context->pos += 4;
    char yes = 1;
    return cfautoreleased(CFNumberCreate(NULL, kCFNumberCharType, &yes));
}

static NSNull* deserializeNull(KSJSONDeserializeContext* context)
{
    const unichar* ch = *context->pos;
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
    *context->pos += 4;
    return (__bridge id)kCFNull;
}

static id deserializeElement(KSJSONDeserializeContext* context)
{
    skipWhitespace(*context->pos, context->end);
    
    switch(**context->pos)
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
    makeError(context->error, @"Unexpected character: %c", **context->pos);
    return nil;
}


static id deserializeArray(KSJSONDeserializeContext* context)
{
    (*context->pos)++;
    CFMutableArrayRef arrayRef = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    NSMutableArray* array = cfautoreleased(arrayRef);
    
    while(*context->pos < context->end)
    {
        skipWhitespace(*context->pos, context->end);
        unlikely_if(**context->pos == ARRAY_END)
        {
            (*context->pos)++;
            return array;
        }
        id element = deserializeElement(context);
        unlikely_if(element == nil)
        {
            return nil;
        }
        skipWhitespace(*context->pos, context->end);
        likely_if(**context->pos == ELEMENT_SEPARATOR)
        {
            (*context->pos)++;
        }
        CFArrayAppendValue(arrayRef, (__bridge CFTypeRef)element);
    }
    makeError(context->error, @"Unterminated array");
    return nil;
}

typedef struct
{
    void** keys;
    void** values;
    unsigned int length;
    unsigned int index;
} Dictionary;

static bool dictInit(Dictionary* dict, NSError** error)
{
    dict->index = 0;
    dict->length = 64;

    dict->keys = malloc(dict->length * sizeof(*dict->keys));
    unlikely_if(dict->keys == NULL)
    {
        makeError(error, @"Out of memory");
        return false;
    }
    dict->values = malloc(dict->length * sizeof(*dict->values));
    unlikely_if(dict->values == NULL)
    {
        makeError(error, @"Out of memory");
        return false;
    }
    return true;
}

static bool dictAddKeyAndValue(Dictionary* dict, id key, id value, NSError** error)
{
    unlikely_if(dict->index >= dict->length)
    {
        dict->length *= 2;
        dict->keys = realloc(dict->keys, dict->length * sizeof(*dict->keys));
        unlikely_if(dict->keys == NULL)
        {
            makeError(error, @"Out of memory");
            return false;
        }
        dict->values = realloc(dict->values, dict->length * sizeof(*dict->values));
        unlikely_if(dict->values == NULL)
        {
            makeError(error, @"Out of memory");
            return false;
        }
    }
    dict->keys[dict->index] = (__bridge void*)key;
    dict->values[dict->index] = (__bridge void*)value;
    dict->index++;
    return true;
}

static void dictFree(Dictionary* dict)
{
    free(dict->keys);
    free(dict->values);
}

static id deserializeDictionary(KSJSONDeserializeContext* context)
{
    (*context->pos)++;
    Dictionary dict;
    unlikely_if(!dictInit(&dict, context->error))
    {
        return nil;
    }
    
    while(*context->pos < context->end)
    {
        skipWhitespace(*context->pos, context->end);
        unlikely_if(**context->pos == DICTIONARY_END)
        {
            (*context->pos)++;
            id result = cfautoreleased(CFDictionaryCreate(NULL,
                                                          (const void**)dict.keys,
                                                          (const void**)dict.values,
                                                          (CFIndex)dict.index,
                                                          &kCFTypeDictionaryKeyCallBacks,
                                                          &kCFTypeDictionaryValueCallBacks));
            dictFree(&dict);
            return result;
        }
        NSString* name = deserializeString(context);
        unlikely_if(name == nil)
        {
            goto failed;
        }
        skipWhitespace(*context->pos, context->end);
        unlikely_if(**context->pos != NAME_SEPARATOR)
        {
            makeError(context->error, @"Expected name separator");
            goto failed;
        }
        (*context->pos)++;
        id element = deserializeElement(context);
        unlikely_if(element == nil)
        {
            goto failed;
        }
        skipWhitespace(*context->pos, context->end);
        likely_if(**context->pos == ELEMENT_SEPARATOR)
        {
            (*context->pos)++;
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


static id deserializeJSON(KSJSONDeserializeContext* context)
{
    skipWhitespace(*context->pos, context->end);
    switch(**context->pos)
    {
        case ARRAY_BEGIN:
            return deserializeArray(context);
            break;
        case DICTIONARY_BEGIN:
            return deserializeDictionary(context);
            break;
    }
    makeError(context->error, @"Unexpected character: %c", **context->pos);
    return nil;
}




#define KSJSON_ScratchBuffSize 1024
#define KSJSON_InitialBuffSize 65536

typedef struct
{
    unichar* buffer;
    unichar scratchBuffer[KSJSON_ScratchBuffSize];
    unsigned int size;
    unsigned int index;
    __autoreleasing NSError** error;
} KSJSONSerializeContext;

static unichar g_false[] = {'f','a','l','s','e'};
static unichar g_true[] = {'t','r','u','e'};
static unichar g_null[] = {'n','u','l','l'};


static bool serializeObject(KSJSONSerializeContext* context, id object);


static bool serializeInit(KSJSONSerializeContext* context)
{
    context->index = 0;
    context->size = KSJSON_InitialBuffSize;
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

static NSString* serializeFinish(KSJSONSerializeContext* context)
{
    return cfautoreleased(CFStringCreateWithCharactersNoCopy(NULL,
                                                             context->buffer,
                                                             (CFIndex)context->index,
                                                             NULL));
}

static void serializeAbort(KSJSONSerializeContext* context)
{
    CFAllocatorDeallocate(NULL, context->buffer);
}

static void serializeChar(KSJSONSerializeContext* context, const unichar ch)
{
    context->buffer[context->index++] = ch;
    unlikely_if(context->index >= context->size)
    {
        serializeRealloc(context, 1);
    }
}

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

static void serializeBacktrack(KSJSONSerializeContext* context,
                               unsigned int numChars)
{
    context->index -= numChars;
}

static bool serializeArray(KSJSONSerializeContext* context, NSArray* array)
{
    CFArrayRef arrayRef = (__bridge CFArrayRef)array;
    CFIndex count = CFArrayGetCount(arrayRef);
    
    unlikely_if(count == 0)
    {
        serialize2Chars(context, '[',']');
        return true;
    }
    serializeChar(context, '[');
    for(CFIndex i = 0; i < count; i++)
    {
        id subObject = (__bridge id) CFArrayGetValueAtIndex(arrayRef, i);
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

#define kDictStackSize 50

static bool serializeDictionary(KSJSONSerializeContext* context,
                                NSDictionary* dict)
{
    bool success = NO;
    CFDictionaryRef dictRef = (__bridge CFDictionaryRef)dict;
    CFIndex count = CFDictionaryGetCount(dictRef);
    
    unlikely_if(count == 0)
    {
        serialize2Chars(context, '{','}');
        return true;
    }
    serializeChar(context, '{');
    const void** keys;
    const void** values;
    void* memory = NULL;
    const void* stackMemory[kDictStackSize * 2];
    likely_if(count <= kDictStackSize)
    {
        keys = stackMemory;
        values = keys + count;
    }
    else
    {
        memory = malloc(sizeof(void*) * (unsigned int)count * 2);
        unlikely_if(memory == NULL)
        {
            makeError(context->error, @"Out of memory");
            return false;
        }
        keys = memory;
        values = keys + count;
    }
    
    
    CFDictionaryGetKeysAndValues(dictRef, keys, values);
    for(CFIndex i = 0; i < count; i++)
    {
        id key = (__bridge id)keys[i];
        id value = (__bridge id)values[i];
        unlikely_if(!serializeObject(context, key))
        {
            goto done;
        }
        serializeChar(context, ':');
        unlikely_if(!serializeObject(context, value))
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

static bool serializeString(KSJSONSerializeContext* context, NSString* string)
{
    void* memory = NULL;
    CFStringRef stringRef = (__bridge CFStringRef)string;
    CFIndex length = CFStringGetLength(stringRef);
    unlikely_if(length == 0)
    {
        serialize2Chars(context, '"', '"');
        return true;
    }
    const unichar* chars = CFStringGetCharactersPtr(stringRef);
    likely_if(chars == NULL)
    {
        likely_if(length <= KSJSON_ScratchBuffSize)
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
        CFStringGetCharacters(stringRef,
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

static void serializeNumberString(KSJSONSerializeContext* context,
                                  const char* numberString)
{
    const char* end = numberString + strlen(numberString);
    for(const char* ch = numberString; ch < end; ch++)
    {
        serializeChar(context, (unichar)*ch);
    }
}

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

static bool serializeNumber(KSJSONSerializeContext* context,
                            NSNumber* number)
{
    CFNumberRef numberRef = (__bridge CFNumberRef)number;
    CFNumberType numberType = CFNumberGetType(numberRef);
    char buff[100];
    switch(numberType)
    {
        case kCFNumberCharType:
        {
            char value;
            CFNumberGetValue(numberRef, numberType, &value);
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
            CFNumberGetValue(numberRef, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberCGFloatType:
        {
            CGFloat value;
            CFNumberGetValue(numberRef, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberDoubleType:
        {
            double value;
            CFNumberGetValue(numberRef, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberFloat32Type:
        {
            Float32 value;
            CFNumberGetValue(numberRef, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberFloat64Type:
        {
            Float64 value;
            CFNumberGetValue(numberRef, numberType, &value);
            snprintf(buff, sizeof(buff), "%g", value);
            serializeNumberString(context, buff);
            return true;
        }
        case kCFNumberIntType:
        {
            int value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberNSIntegerType:
        {
            NSInteger value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberLongType:
        {
            long value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberLongLongType:
        {
            long long value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberShortType:
        {
            short value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberSInt16Type:
        {
            SInt16 value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberSInt32Type:
        {
            SInt32 value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberSInt64Type:
        {
            SInt64 value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberSInt8Type:
        {
            SInt8 value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
        case kCFNumberCFIndexType:
        {
            CFIndex value;
            CFNumberGetValue(numberRef, numberType, &value);
            serializeInteger(context, value);
            return true;
        }
    }
    return serializeString(context, [number stringValue]);
}

static bool serializeNull(KSJSONSerializeContext* context, id object)
{
    serializeChars(context, g_null, 4);
    return true;
}


typedef bool (*serializeFunction)(KSJSONSerializeContext* context, id object);

typedef enum
{
    KSJSON_ClassString,
    KSJSON_ClassNumber,
    KSJSON_ClassArray,
    KSJSON_ClassDictionary,
    KSJSON_ClassNull,
    KSJSON_ClassCount,
} KSJSON_Class;

static Class g_classCache[KSJSON_ClassCount];
static const serializeFunction g_serializeFunctions[] =
{
    serializeString,
    serializeNumber,
    serializeArray,
    serializeDictionary,
    serializeNull,
};

static bool serializeObject(KSJSONSerializeContext* context, id object)
{
    Class cls = object_getClass(object);
    for(KSJSON_Class i = 0; i < KSJSON_ClassCount; i++)
    {
        unlikely_if(g_classCache[i] == cls)
        {
            return g_serializeFunctions[i](context, object);
        }
    }
    
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
    return g_serializeFunctions[classType](context, object);
}

@implementation KSJSON

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
    
    likely_if(serializeObject(&context, object))
    {
        return serializeFinish(&context);
    }
    
    serializeAbort(&context);
    return nil;
}

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
    unichar* chars = start;
    unichar* end = start + length;
    KSJSONDeserializeContext context =
    {
        &chars,
        end,
        error
    };
    
    id result = deserializeJSON(&context);
    unlikely_if(error != nil && *error != nil)
    {
        NSString* desc = [(*error).userInfo valueForKey:NSLocalizedDescriptionKey];
        desc = [desc stringByAppendingFormat:@" (at offset %d)", chars - start];
        *error = [NSError errorWithDomain:@"KSJSON"
                                     code:1
                                 userInfo:[NSDictionary dictionaryWithObject:desc
                                                                      forKey:NSLocalizedDescriptionKey]];
    }
    
    free(start);
    return result;
}

@end
