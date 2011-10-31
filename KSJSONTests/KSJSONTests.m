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

- (void)testArrayEmpty
{
    NSString* expected = @"[]";
    id original = [NSArray array];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testArrayNull
{
    NSString* expected = @"[null]";
    id original = [NSArray arrayWithObjects:
                   [NSNull null],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testArrayBoolTrue
{
    NSString* expected = @"[true]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithBool:YES],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testArrayBoolFalse
{
    NSString* expected = @"[false]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithBool:NO],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testArrayInteger
{
    NSString* expected = @"[1]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithInt:1],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testArrayFloat
{
    NSString* expected = @"[-0.2]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithFloat:-0.2f],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEquals([[result objectAtIndex:0] floatValue], -0.2f, @"");
    // This always fails on NSNumber filled with float.
    //STAssertEqualObjects(result, original, @"");
}

- (void) testArrayFloat2
{
    NSString* expected = @"[-2e-15]";
    id original = [NSArray arrayWithObjects:
                   [NSNumber numberWithFloat:-2e-15f],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEquals([[result objectAtIndex:0] floatValue], -2e-15f, @"");
    // This always fails on NSNumber filled with float.
    //STAssertEqualObjects(result, original, @"");
}

- (void)testArrayString
{
    NSString* expected = @"[\"One\"]";
    id original = [NSArray arrayWithObjects:
                   @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testArrayMultipleEntries
{
    NSString* expected = @"[\"One\",1000,true]";
    id original = [NSArray arrayWithObjects:
                   @"One",
                   [NSNumber numberWithInt:1000],
                   [NSNumber numberWithBool:YES],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testArrayWithArray
{
    NSString* expected = @"[[]]";
    id original = [NSArray arrayWithObjects:
                   [NSArray array],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testArrayWithArray2
{
    NSString* expected = @"[[\"Blah\"]]";
    id original = [NSArray arrayWithObjects:
                   [NSArray arrayWithObjects:@"Blah", nil],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testArrayWithDictionary
{
    NSString* expected = @"[{}]";
    id original = [NSArray arrayWithObjects:
                   [NSDictionary dictionary],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testArrayWithDictionary2
{
    NSString* expected = @"[{\"Blah\":true}]";
    id original = [NSArray arrayWithObjects:
                   [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithBool:YES], @"Blah",
                    nil],
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}


- (void)testDictionaryEmpty
{
    NSString* expected = @"{}";
    id original = [NSDictionary dictionary];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testDictionaryNull
{
    NSString* expected = @"{\"One\":null}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNull null], @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testDictionaryBoolTrue
{
    NSString* expected = @"{\"One\":true}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithBool:YES], @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testDictionaryBoolFalse
{
    NSString* expected = @"{\"One\":false}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithBool:NO], @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testDictionaryInteger
{
    NSString* expected = @"{\"One\":1}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithInt:1], @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testDictionaryFloat
{
    NSString* expected = @"{\"One\":54.918}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithFloat:54.918f], @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEquals([[result objectForKey:@"One"] floatValue], 54.918f, @"");
    // This always fails on NSNumber filled with float.
    //STAssertEqualObjects(result, original, @"");
}

- (void) testDictionaryFloat2
{
    NSString* expected = @"{\"One\":5e+20}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithFloat:5e20f], @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEquals([[result objectForKey:@"One"] floatValue], 5e20f, @"");
    // This always fails on NSNumber filled with float.
    //STAssertEqualObjects(result, original, @"");
}

- (void)testDictionaryString
{
    NSString* expected = @"{\"One\":\"Value\"}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   @"Value", @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testDictionaryMultipleEntries
{
    NSString* expected = @"{\"One\":\"Value\",\"Two\":1000,\"Three\":true}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   @"Value", @"One",
                   [NSNumber numberWithInt:1000], @"Two",
                   [NSNumber numberWithBool:YES], @"Three",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testDictionaryWithDictionary
{
    NSString* expected = @"{\"One\":{}}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSDictionary dictionary], @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testDictionaryWithDictionary2
{
    NSString* expected = @"{\"One\":{\"Blah\":1}}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithInt:1], @"Blah",
                    nil], @"One",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testDictionaryWithArray
{
    NSString* expected = @"{\"Key\":[]}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSArray array], @"Key",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void)testDictionaryWithArray2
{
    NSString* expected = @"{\"Blah\":[true]}";
    id original = [NSDictionary dictionaryWithObjectsAndKeys:
                   [NSArray arrayWithObject:[NSNumber numberWithBool:YES]], @"Blah",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

- (void) testUnicode
{
    NSString* json = @"[\"\\u00dcOne\"]";
    NSString* expected = @"\u00dcOne";
    NSArray* result = [KSJSON deserializeString:json];
    STAssertNotNil(result, @"");
    NSString* value = [result objectAtIndex:0];
    STAssertEqualObjects(value, expected, @"");
}

- (void) testUnicode2
{
    NSString* json = @"[\"\\u827e\\u5c0f\\u8587\"]";
    NSString* expected = @"\u827e\u5c0f\u8587";
    NSArray* result = [KSJSON deserializeString:json];
    STAssertNotNil(result, @"");
    NSString* value = [result objectAtIndex:0];
    STAssertEqualObjects(value, expected, @"");
}

- (void) testControlCharsDeserialize
{
    NSString* json = @"[\"\\b\\f\\n\\r\\t\"]";
    NSString* expected = @"\b\f\n\r\t";
    NSArray* result = [KSJSON deserializeString:json];
    STAssertNotNil(result, @"");
    NSString* value = [result objectAtIndex:0];
    STAssertEqualObjects(value, expected, @"");
}

- (void) testControlCharsSerialize
{
    NSString* expected = @"[\"\\b\\f\\n\\r\\t\"]";
    id original = [NSArray arrayWithObjects:
                   @"\b\f\n\r\t",
                   nil];
    NSString* jsonString = [KSJSON serializeObject:original];
    STAssertNotNil(jsonString, @"");
    STAssertEqualObjects(jsonString, expected, @"");
    id result = [KSJSON deserializeString:jsonString];
    STAssertNotNil(result, @"");
    STAssertEqualObjects(result, original, @"");
}

@end
