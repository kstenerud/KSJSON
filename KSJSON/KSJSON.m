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


static id deserializeJSON(const unichar** pos, const unichar* end);
static id deserializeElement(const unichar** pos, const unichar* end);
static id deserializeArray(const unichar** pos, const unichar* end);
static id deserializeDictionary(const unichar** pos, const unichar* end);
static NSString* deserializeString(const unichar** pos, const unichar* end);


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

static bool parseUnicodeSequence(const unichar* start, unichar* dst)
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
            NSLog(@"KSJSON: Invalid unicode sequence");
            return false;
        }
        accum = (unichar)((accum << 4) + g_hexConversion[next]);
    }
    *dst = accum;
    return true;
}

static NSString* parseString(const unichar* ch, const unichar* end)
{
    NSString* result = nil;
    unsigned int length = (unsigned int)(end - ch);
    unichar* string = malloc(length * sizeof(*string));
    unlikely_if(string == NULL)
    {
        NSLog(@"KSJSON: Out of memory");
        return nil;
    }
    unichar* pStr = string;
    
    for(;ch < end; ch++)
    {
        likely_if(*ch != '\\')
        {
            *pStr++ = *ch;
        }
        else
        {
            ch++;
            length--; // Skipped a backslash.
            unlikely_if(ch >= end)
            {
                NSLog(@"KSJSON: Unterminated escape sequence");
                goto fail;
            }
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
                    unlikely_if(ch > end - 4)
                {
                    NSLog(@"KSJSON: Unterminated escape sequence");
                    goto fail;
                }
                    unlikely_if(!parseUnicodeSequence(ch, pStr++))
                {
                    goto fail;
                }
                    ch += 3;
                    length -= 4; // Replaced 5 chars with 1.
                    break;
                default:
                    NSLog(@"KSJSON: Invalid escape sequence");
                    goto fail;
            }
        }
    }
    
    result = [NSString stringWithCharacters:string length:length];
fail:
    free(string);
    return result;
}

static NSString* deserializeString(const unichar** pos, const unichar* end)
{
    const unichar* ch = *pos + 1;
    const unichar* start = ch;
    for(;ch < end; ch++)
    {
        unlikely_if(*ch == '\\')
        {
            ch++;
        }
        else unlikely_if(*ch == '"')
        {
            break;
        }
    }
    
    unlikely_if(ch >= end)
    {
        NSLog(@"KSJSON: Unterminated string");
        return nil;
    }
    
    *pos = ch + 1;
    return parseString(start, ch);
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

static NSNumber* deserializeNumber(const unichar** pos, const unichar* end)
{
    const unichar* start = *pos;
    const unichar* ch = *pos;
    long long accum = 0;
    long long sign = *ch == '-' ? -1 : 1;
    if(sign == -1)
    {
        ch++;
    }
    
    for(;ch < end && isdigit(*ch); ch++)
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
        *pos = ch;
        return [NSNumber numberWithLongLong:accum];
    }
    
    for(;ch < end && isFPChar(*ch); ch++)
    {
    }
    
    *pos = ch;
    
    NSString* string = [NSString stringWithCharacters:start
                                               length:(NSUInteger)(ch - start)];
    return [NSDecimalNumber decimalNumberWithString:string];
}

static NSNumber* deserializeFalse(const unichar** pos, const unichar* end)
{
    const unichar* ch = *pos;
    unlikely_if(end - ch < 5)
    {
        NSLog(@"KSJSON: Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(ch[1] == 'a' && ch[2] == 'l' && ch[3] == 's' && ch[4] == 'e'))
    {
        NSLog(@"KSJSON: Invalid characters while parsing 'false'");
        return nil;
    }
    *pos += 5;
    return [NSNumber numberWithBool:NO];
}

static NSNumber* deserializeTrue(const unichar** pos, const unichar* end)
{
    const unichar* ch = *pos;
    unlikely_if(end - ch < 4)
    {
        NSLog(@"KSJSON: Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(ch[1] == 'r' && ch[2] == 'u' && ch[3] == 'e'))
    {
        NSLog(@"KSJSON: Invalid characters while parsing 'true'");
        return nil;
    }
    *pos += 4;
    return [NSNumber numberWithBool:YES];
}

static NSNull* deserializeNull(const unichar** pos, const unichar* end)
{
    const unichar* ch = *pos;
    unlikely_if(end - ch < 4)
    {
        NSLog(@"KSJSON: Premature end of JSON data");
        return nil;
    }
    unlikely_if(!(ch[1] == 'u' && ch[2] == 'l' && ch[3] == 'l'))
    {
        NSLog(@"KSJSON: Invalid characters while parsing 'null'");
        return nil;
    }
    *pos += 4;
    return [NSNull null];
}

static id deserializeElement(const unichar** pos, const unichar* end)
{
    skipWhitespace(*pos, end);
    
    switch(**pos)
    {
        case ARRAY_BEGIN:
            return deserializeArray(pos, end);
        case DICTIONARY_BEGIN:
            return deserializeDictionary(pos, end);
        case STRING_BEGIN:
            return deserializeString(pos, end);
        case FALSE_BEGIN:
            return deserializeFalse(pos, end);
        case TRUE_BEGIN:
            return deserializeTrue(pos, end);
        case NULL_BEGIN:
            return deserializeNull(pos, end);
        case '0': case '1': case '2': case '3': case '4':
        case '5': case '6': case '7': case '8': case '9':
        case '-': // Begin number
            return deserializeNumber(pos, end);
    }
    NSLog(@"KSJSON: Unexpected character: %c", **pos);
    return nil;
}


static id deserializeArray(const unichar** pos, const unichar* end)
{
    (*pos)++;
    NSMutableArray* array = [NSMutableArray array];
    while(*pos < end)
    {
        skipWhitespace(*pos, end);
        unlikely_if(**pos == ARRAY_END)
        {
            (*pos)++;
            return array;
        }
        id element = deserializeElement(pos, end);
        unlikely_if(element == nil)
        {
            return nil;
        }
        skipWhitespace(*pos, end);
        likely_if(**pos == ELEMENT_SEPARATOR)
        {
            (*pos)++;
        }
        [array addObject:element];
    }
    NSLog(@"KSJSON: Unterminated array");
    return nil;
}

static id deserializeDictionary(const unichar** pos, const unichar* end)
{
    (*pos)++;
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    while(*pos < end)
    {
        skipWhitespace(*pos, end);
        unlikely_if(**pos == DICTIONARY_END)
        {
            (*pos)++;
            return dict;
        }
        NSString* name = deserializeString(pos, end);
        unlikely_if(name == nil)
        {
            return nil;
        }
        skipWhitespace(*pos, end);
        unlikely_if(**pos != NAME_SEPARATOR)
        {
            NSLog(@"KSJSON: Expected name separator");
        }
        (*pos)++;
        id element = deserializeElement(pos, end);
        unlikely_if(element == nil)
        {
            return nil;
        }
        skipWhitespace(*pos, end);
        likely_if(**pos == ELEMENT_SEPARATOR)
        {
            (*pos)++;
        }
        [dict setValue:element forKey:name];
    }
    NSLog(@"KSJSON: Unterminated object");
    return nil;
}


static id deserializeJSON(const unichar** pos, const unichar* end)
{
    skipWhitespace(*pos, end);
    switch(**pos)
    {
        case ARRAY_BEGIN:
            return deserializeArray(pos, end);
            break;
        case DICTIONARY_BEGIN:
            return deserializeDictionary(pos, end);
            break;
    }
    NSLog(@"KSJSON: Unexpected character: %c", **pos);
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
} KSJSONSerializeContext;

static unichar g_false[] = {'f','a','l','s','e'};
static unichar g_true[] = {'t','r','u','e'};
static unichar g_null[] = {'n','u','l','l'};


static bool serializeObject(KSJSONSerializeContext* context, id object);


static bool serializeInit(KSJSONSerializeContext* context)
{
    context->index = 0;
    context->size = KSJSON_InitialBuffSize;
    context->buffer = malloc(sizeof(context->buffer[0]) * context->size);
    unlikely_if(context->buffer == NULL)
    {
        NSLog(@"KSJSON: Out of memory");
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
    context->buffer = realloc(context->buffer,
                              sizeof(context->buffer[0]) * context->size);
    unlikely_if(context->buffer == NULL)
    {
        NSLog(@"KSJSON: Out of memory");
        return false;
    }
    return true;
}

static NSString* serializeFinish(KSJSONSerializeContext* context)
{
    NSString* string = [NSString stringWithCharacters:context->buffer
                                               length:context->index];
    free(context->buffer);
    return string;
}

static void serializeAbort(KSJSONSerializeContext* context)
{
    free(context->buffer);
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
            NSLog(@"KSJSON: Out of memory");
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
                NSLog(@"KSJSON: Out of memory");
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
                    // TODO: Encode hex sequence? OR error?
                    break;
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
            if([number boolValue])
            {
                serializeChars(context, g_true, 4);
            }
            else
            {
                serializeChars(context, g_false, 5);
            }
            return true;
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

static bool serializeUnknown(KSJSONSerializeContext* context, id object)
{
    NSLog(@"KSJSON: Cannot serialize object of type %@", [object class]);
    return false;
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
    serializeUnknown,
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
    else if(object == nil)
    {
        classType = KSJSON_ClassNull;
    }
    
    g_classCache[classType] = cls;
    return g_serializeFunctions[classType](context, object);
}

@implementation KSJSON

+ (NSString*) serializeObject:(id) object
{
    unlikely_if(![object isKindOfClass:[NSArray class]] &&
                ![object isKindOfClass:[NSDictionary class]])
    {
        NSLog(@"KSJSON: Top level object must be an array or dictionary.");
        return nil;
    }
    KSJSONSerializeContext context;
    serializeInit(&context);
    
    likely_if(serializeObject(&context, object))
    {
        return serializeFinish(&context);
    }
    
    serializeAbort(&context);
    return nil;
}

+ (id) deserializeString:(NSString*) jsonString
{
    void* memory = NULL;
    unsigned int length = [jsonString length];
    const unichar* chars = CFStringGetCharactersPtr((__bridge CFStringRef)jsonString);
    likely_if(chars == NULL)
    {
        memory = malloc(length * sizeof(*chars));
        [jsonString getCharacters:(unichar*)memory
                            range:NSMakeRange(0, length)];
        chars = memory;
    }
    const unichar* start = chars;
    const unichar* end = chars + length;
    
    id result = deserializeJSON(&chars, end);
    unlikely_if(result == nil)
    {
        NSLog(@"At offset %d", chars - start);
    }
    
    likely_if(memory != NULL)
    {
        free(memory);
    }
    return result;
}

@end
