//
//  KSJSONTests.m
//  KSJSONTests
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

#import <SenTestingKit/SenTestingKit.h>

#import "KSJSON.h"

@interface KSJSONTests : SenTestCase {} @end

@implementation KSJSONTests

static NSString* makeString(NSData* data)
{
    if(data == nil)
    {
        return nil;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSData* makeData(NSString* string)
{
    if(string == nil)
    {
        return nil;
    }
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)testSerializeDeserializeNilError
{
    NSString* expected = @"[]";
    id original = [NSArray array];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:nil]);
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:nil];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}


- (void)testSerializeDeserializeArrayEmpty
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[]";
    id original = [NSArray array];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeArrayNull
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[null]";
    id original = [NSArray arrayWithObjects:
                   [NSNull null],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeArrayBoolTrue
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[true]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithBool:YES],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeArrayBoolFalse
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[false]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithBool:NO],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeArrayInteger
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[1]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithInt:1],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeArrayFloat
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[-2e-15]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithFloat:-2e-15f],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEquals([[result objectAtIndex:0] floatValue], -2e-15f, @"");
    // This always fails on NSNumber filled with float.
    //STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayString
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[\"One\"]";
    id original = [NSArray arrayWithObjects:
                   @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayMultipleEntries
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[\"One\",1000,true]";
    id original = [NSArray arrayWithObjects:
                   @"One",
                   [NSNumber numberWithInt:1000],
                   [NSNumber numberWithBool:YES],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayWithArray
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[[]]";
    id original = [NSArray arrayWithObjects:
                   [NSArray array],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayWithArray2
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[[\"Blah\"]]";
    id original = [NSArray arrayWithObjects:
                   [NSArray arrayWithObjects:@"Blah", nil],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayWithDictionary
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[{}]";
    id original = [NSArray arrayWithObjects:
                   [NSDictionary dictionary],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeArrayWithDictionary2
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[{\"Blah\":true}]";
    id original = [NSArray arrayWithObjects:
                   [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithBool:YES], @"Blah",
                    nil],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}


- (void)testSerializeDeserializeDictionaryEmpty
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{}";
    id original = [NSDictionary dictionary];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeDictionaryNull
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":null}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNull null], @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeDictionaryBoolTrue
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":true}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithBool:YES], @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeDictionaryBoolFalse
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":false}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithBool:NO], @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeDictionaryInteger
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":1}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithInt:1], @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeDictionaryFloat
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":54.918}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithFloat:54.918f], @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEquals([[result objectForKey:@"One"] floatValue], 54.918f, @"");
    // This always fails on NSNumber filled with float.
    //STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeDictionaryFloat2
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":5e+20}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithFloat:5e20f], @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEquals([[result objectForKey:@"One"] floatValue], 5e20f, @"");
    // This always fails on NSNumber filled with float.
    //STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryString
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":\"Value\"}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   @"Value", @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryMultipleEntries
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":\"Value\",\"Two\":1000,\"Three\":true}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   @"Value", @"One",
                   [NSNumber numberWithInt:1000], @"Two",
                   [NSNumber numberWithBool:YES], @"Three",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryWithDictionary
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":{}}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSDictionary dictionary], @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryWithDictionary2
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"One\":{\"Blah\":1}}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithInt:1], @"Blah",
                    nil], @"One",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryWithArray
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"Key\":[]}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSArray array], @"Key",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeDictionaryWithArray2
{
    NSError* error = (NSError*)self;
    NSString* expected = @"{\"Blah\":[true]}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSArray arrayWithObject:[NSNumber numberWithBool:YES]], @"Blah",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testSerializeDeserializeBigDictionary
{
    NSError* error = (NSError*)self;
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   @"0", @"0",
                   @"1", @"1",
                   @"2", @"2",
                   @"3", @"3",
                   @"4", @"4",
                   @"5", @"5",
                   @"6", @"6",
                   @"7", @"7",
                   @"8", @"8",
                   @"9", @"9",
                   @"10", @"10",
                   @"11", @"11",
                   @"12", @"12",
                   @"13", @"13",
                   @"14", @"14",
                   @"15", @"15",
                   @"16", @"16",
                   @"17", @"17",
                   @"18", @"18",
                   @"19", @"19",
                   @"20", @"20",
                   @"21", @"21",
                   @"22", @"22",
                   @"23", @"23",
                   @"24", @"24",
                   @"25", @"25",
                   @"26", @"26",
                   @"27", @"27",
                   @"28", @"28",
                   @"29", @"29",
                   @"30", @"30",
                   @"31", @"31",
                   @"32", @"32",
                   @"33", @"33",
                   @"34", @"34",
                   @"35", @"35",
                   @"36", @"36",
                   @"37", @"37",
                   @"38", @"38",
                   @"39", @"39",
                   @"40", @"40",
                   @"41", @"41",
                   @"42", @"42",
                   @"43", @"43",
                   @"44", @"44",
                   @"45", @"45",
                   @"46", @"46",
                   @"47", @"47",
                   @"48", @"48",
                   @"49", @"49",
                   @"50", @"50",
                   @"51", @"51",
                   @"52", @"52",
                   @"53", @"53",
                   @"54", @"54",
                   @"55", @"55",
                   @"56", @"56",
                   @"57", @"57",
                   @"58", @"58",
                   @"59", @"59",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testDeserializeUnicode
{
    NSError* error = (NSError*)self;
    NSString* json = @"[\"\\u00dcOne\"]";
    NSString* expected = @"\u00dcOne";
    NSArray* result = [KSJSON deserializeData:makeData(json) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    NSString* value = [result objectAtIndex:0];
    STAssertEqualObjects(value, expected, @"");
}

- (void) testDeserializeUnicode2
{
    NSError* error = (NSError*)self;
    NSString* json = @"[\"\\u827e\\u5c0f\\u8587\"]";
    NSString* expected = @"\u827e\u5c0f\u8587";
    NSArray* result = [KSJSON deserializeData:makeData(json) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    NSString* value = [result objectAtIndex:0];
    STAssertEqualObjects(value, expected, @"");
}

- (void) testDeserializeUnicode3
{
    NSError* error = (NSError*)self;
    NSString* json = @"[\"\u8717\u725b\u6709\u623f\u5b50\uff01RT @zqzx: \u8774\u8776\u4e3a\u4ec0\u4e48\u5ac1\u7ed9\u8717\u725b\uff1f: http://bit.ly/F551P\"]";
    NSString* expected = @"蜗牛有房子！RT @zqzx: 蝴蝶为什么嫁给蜗牛？: http://bit.ly/F551P";
    NSArray* result = [KSJSON deserializeData:makeData(json) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    NSString* value = [result objectAtIndex:0];
    STAssertEqualObjects(value, expected, @"");
}

- (void) testDeserializeUnicode4
{
    NSError* error = (NSError*)self;
    NSString* json = @"[\"\\u0020One\"]";
    NSString* expected = @" One";
    NSArray* result = [KSJSON deserializeData:makeData(json) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    NSString* value = [result objectAtIndex:0];
    STAssertEqualObjects(value, expected, @"");
}

- (void) testDeserializeControlChars
{
    NSError* error = (NSError*)self;
    NSString* json = @"[\"\\b\\f\\n\\r\\t\"]";
    NSString* expected = @"\b\f\n\r\t";
    NSArray* result = [KSJSON deserializeData:makeData(json) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    NSString* value = [result objectAtIndex:0];
    STAssertEqualObjects(value, expected, @"");
}

- (void) testSerializeDeserializeControlChars2
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[\"\\b\\f\\n\\r\\t\"]";
    id original = [NSArray arrayWithObjects:
                   @"\b\f\n\r\t",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeEscapedChars
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[\"\\\"\\\\\"]";
    id original = [NSArray arrayWithObjects:
                   @"\"\\",
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}




- (void) testDeserializeQuoted
{
    NSError* error = (NSError*)self;
    NSString* json = @"[{\"geo\":null,\"in_reply_to_user_id\":null,\"in_reply_to_status_id\":null,\"truncated\":false,\"source\":\"web\",\"favorited\":false,\"created_at\":\"Wed Nov 04 07:20:37 +0000 2009\",\"in_reply_to_screen_name\":null,\"user\":{\"notifications\":null,\"favourites_count\":0,\"description\":\"AdMan / Music Collector\",\"following\":null,\"statuses_count\":617,\"profile_text_color\":\"8c8c8c\",\"geo_enabled\":false,\"profile_background_image_url\":\"http://s.twimg.com/a/1257288876/images/themes/theme9/bg.gif\",\"profile_image_url\":\"http://a3.twimg.com/profile_images/503330459/madmen_icon_normal.jpg\",\"profile_link_color\":\"2FC2EF\",\"verified\":false,\"profile_background_tile\":false,\"url\":null,\"screen_name\":\"khaled_itani\",\"created_at\":\"Thu Jul 23 20:39:21 +0000 2009\",\"profile_background_color\":\"1A1B1F\",\"profile_sidebar_fill_color\":\"252429\",\"followers_count\":156,\"protected\":false,\"location\":\"Tempe, Arizona\",\"name\":\"Khaled Itani\",\"time_zone\":\"Pacific Time (US & Canada)\",\"friends_count\":151,\"profile_sidebar_border_color\":\"050505\",\"id\":59581900,\"utc_offset\":-28800},\"id\":5414922107,\"text\":\"RT @cakeforthought 24. If you wish hard enough, you will hear your current favourite song on the radio minutes after you get into your car.\"},{\"geo\":null,\"in_reply_to_user_id\":null,\"in_reply_to_status_id\":null,\"truncated\":false,\"source\":\"<a href=\\\"http://www.hootsuite.com\\\" rel=\\\"nofollow\\\">HootSuite</a>\",\"favorited\":false,\"created_at\":\"Wed Nov 04 07:20:37 +0000 2009\",\"in_reply_to_screen_name\":null,\"user\":{\"geo_enabled\":false,\"description\":\"80\\u540e\\uff0c\\u5904\\u5973\\u5ea7\\uff0c\\u65e0\\u4e3b\\u7684\\u808b\\u9aa8\\uff0c\\u5b85+\\u5fae\\u8150\\u3002\\u5b8c\\u7f8e\\u63a7\\uff0c\\u7ea0\\u7ed3\\u63a7\\u3002\\u5728\\u76f8\\u4eb2\\u7684\\u6253\\u51fb\\u4e0e\\u88ab\\u6253\\u51fb\\u4e2d\\u4e0d\\u65ad\\u6210\\u957fing\",\"following\":false,\"profile_text_color\":\"000000\",\"verified\":false,\"profile_background_image_url\":\"http://s.twimg.com/a/1257210731/images/themes/theme1/bg.png\",\"profile_image_url\":\"http://a1.twimg.com/profile_images/326632226/1_normal.jpg\",\"profile_link_color\":\"0000ff\",\"followers_count\":572,\"profile_background_tile\":false,\"url\":null,\"screen_name\":\"ivy_shi0905\",\"created_at\":\"Wed Jul 22 04:15:56 +0000 2009\",\"friends_count\":102,\"profile_background_color\":\"9ae4e8\",\"notifications\":false,\"favourites_count\":0,\"profile_sidebar_fill_color\":\"e0ff92\",\"protected\":false,\"location\":\"Shanghai\",\"name\":\"\\u827e\\u5c0f\\u8587\",\"statuses_count\":1341,\"time_zone\":\"Beijing\",\"profile_sidebar_border_color\":\"87bc44\",\"id\":59032339,\"utc_offset\":28800},\"id\":5414922106,\"text\":\"\\u8717\\u725b\\u6709\\u623f\\u5b50\\uff01RT @zqzx: \\u8774\\u8776\\u4e3a\\u4ec0\\u4e48\\u5ac1\\u7ed9\\u8717\\u725b\\uff1f: http://bit.ly/F551P\"}]";
    NSString* expectedSource = @"<a href=\"http://www.hootsuite.com\" rel=\"nofollow\">HootSuite</a>";
    NSArray* array = [KSJSON deserializeData:[json dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    NSDictionary* result = [array objectAtIndex:1];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects([result valueForKey:@"source"], expectedSource, @"");
}


- (void) testSerializeDeserializeFloat
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[1.2]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithFloat:1.2f],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertTrue([[result objectAtIndex:0] floatValue] ==  [[original objectAtIndex:0] floatValue], @"");
}

- (void) testSerializeDeserializeDouble
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[1.2]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithDouble:1.2f],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertTrue([[result objectAtIndex:0] floatValue] ==  [[original objectAtIndex:0] floatValue], @"");
}

- (void) testSerializeDeserializeChar
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[20]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithChar:20],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeShort
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[2000]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithShort:2000],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeLong
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[2000000000]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithLong:2000000000],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeLongLong
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[200000000000]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithLongLong:200000000000],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeNegative
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[-2000]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithInt:-2000],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserialize0
{
    NSError* error = (NSError*)self;
    NSString* expected = @"[0]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithInt:0],
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeEmptyString
{
    NSError* error = (NSError*)self;
    NSString* string = @"";
    NSString* expected = @"[\"\"]";
    id original = [NSArray arrayWithObjects:
                   string,
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeBigString
{
    NSError* error = (NSError*)self;

    unsigned int length = 500;
    NSMutableString* string = [NSMutableString stringWithCapacity:length];
    for(unsigned int i = 0; i < length; i++)
    {
        [string appendFormat:@"%d", i%10];
    }

    NSString* expected = [NSString stringWithFormat:@"[\"%@\"]", string];
    id original = [NSArray arrayWithObjects:
                   string,
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeHugeString
{
    NSError* error = (NSError*)self;
    char buff[100000];
    memset(buff, '2', sizeof(buff));
    buff[sizeof(buff)-1] = 0;
    NSString* string = [NSString stringWithCString:buff encoding:NSUTF8StringEncoding];
    
    id original = [NSArray arrayWithObjects:
                   string,
                   nil];
    NSString* jsonString = makeString([KSJSON serializeObject:original error:&error]);
    STAssertNotNil(jsonString, @"");
    STAssertNil(error, @"");
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testSerializeDeserializeLargeArray
{
    NSError* error = (NSError*)self;
    unsigned int numEntries = 2000;

    NSMutableString* jsonString = [NSMutableString string];
    [jsonString appendString:@"["];
    for(unsigned int i = 0; i < numEntries; i++)
    {
        [jsonString appendFormat:@"%d,", i%10];
    }
    [jsonString deleteCharactersInRange:NSMakeRange([jsonString length]-1, 1)];
    [jsonString appendString:@"]"];

    id deserialized = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(deserialized, @"");
    STAssertNil(error, @"");
    STAssertEquals([deserialized count], numEntries, @"");
    NSString* serialized = makeString([KSJSON serializeObject:deserialized error:&error]);
    STAssertNotNil(serialized, @"");
    STAssertNil(error, @"");
    STAssertEqualObjects(serialized, jsonString, @"");
    int value = [[deserialized objectAtIndex:1] intValue];
    STAssertEquals(value, 1, @"");
    value = [[deserialized objectAtIndex:9] intValue];
    STAssertEquals(value, 9, @"");
}

- (void) testSerializeDeserializeLargeDictionary
{
    NSError* error = (NSError*)self;
    unsigned int numEntries = 2000;
    
    NSMutableString* jsonString = [NSMutableString string];
    [jsonString appendString:@"{"];
    for(unsigned int i = 0; i < numEntries; i++)
    {
        [jsonString appendFormat:@"\"%d\":%d,", i, i];
    }
    [jsonString deleteCharactersInRange:NSMakeRange([jsonString length]-1, 1)];
    [jsonString appendString:@"}"];
    
    id deserialized = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(deserialized, @"");
    STAssertNil(error, @"");
    STAssertEquals([deserialized count], numEntries, @"");
    int value = [[deserialized objectForKey:@"1"] intValue];
    STAssertEquals(value, 1, @"");
    NSString* serialized = makeString([KSJSON serializeObject:deserialized error:&error]);
    STAssertNotNil(serialized, @"");
    STAssertNil(error, @"");
    STAssertTrue([serialized length] == [jsonString length], @"");
}

- (void) testDeserializeArrayMissingTerminator
{
    NSError* error = (NSError*)self;
    NSString* json = @"[\"blah\"";
    NSArray* result = [KSJSON deserializeData:makeData(json) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void) testSerializeNil
{
    NSError* error = (NSError*)self;
    id source = nil;
    NSString* result = makeString([KSJSON serializeObject:source error:&error]);
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void) testSerializeBadTopLevelType
{
    NSError* error = (NSError*)self;
    id source = @"Blah";
    NSString* result = makeString([KSJSON serializeObject:source error:&error]);
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void) testSerializeArrayBadType
{
    NSError* error = (NSError*)self;
    id source = [NSArray arrayWithObject:[NSValue valueWithPointer:NULL]];
    NSString* result = makeString([KSJSON serializeObject:source error:&error]);
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void) testSerializeDictionaryBadType
{
    NSError* error = (NSError*)self;
    id source = [NSDictionary dictionaryWithObject:[NSValue valueWithPointer:NULL] forKey:@"blah"];
    NSString* result = makeString([KSJSON serializeObject:source error:&error]);
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void) testSerializeDictionaryBadCharacter
{
    NSError* error = (NSError*)self;
    id source = [NSDictionary dictionaryWithObject:@"blah" forKey:@"blah\x01blah"];
    NSString* result = makeString([KSJSON serializeObject:source error:&error]);
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void) testSerializeArrayBadCharacter
{
    NSError* error = (NSError*)self;
    id source = [NSArray arrayWithObject:@"test\x01ing"];
    NSString* result = makeString([KSJSON serializeObject:source error:&error]);
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidUnicodeSequence
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[\"One\\ubarfTwo\"]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidUnicodeSequence2
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[\"One\\uXTwo\"]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidUnicodeSequence3
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[\"One\\u0XTwo\"]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminatedEscape
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[\"One\\u123\"]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminatedEscape2
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[\"One\\\"]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminatedEscape3
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[\"One\\u\"]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidEscape
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[\"One\\qTwo\"]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayUnterminatedString
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[\"One]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayTruncatedFalse
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[f]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidFalse
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[falst]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayTruncatedTrue
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[t]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidTrue
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[ture]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayTruncatedNull
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[n]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidNull
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[nlll]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayInvalidElement
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[-blah]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeArrayNumberOverflow
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"[123456789012345678901234567890]";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNotNil(result, @"");
    STAssertNil(error, @"");
}

- (void)testDeserializeDictionaryInvalidKey
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"{blah:\"blah\"}";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeDictionaryMissingSeparator
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"{\"blah\"\"blah\"}";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeDictionaryBadElement
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"{\"blah\":blah\"}";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeDictionaryUnterminated
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"{\"blah\":\"blah\"";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeInvalidData
{
    NSError* error = (NSError*)self;
    NSString* jsonString = @"X{\"blah\":\"blah\"}";
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

- (void)testDeserializeNil
{
    NSError* error = (NSError*)self;
    NSString* jsonString = nil;
    id result = [KSJSON deserializeData:makeData(jsonString) error:&error];
    STAssertNil(result, @"");
    STAssertNotNil(error, @"");
}

@end
