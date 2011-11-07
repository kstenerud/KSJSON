KSJSON
======

The fastest JSON parser and serializer for Objective-C.



Why KSJSON?
-----------

### It's Fast!

KSJSON is simply the fastest Objective-C based JSON converter there is.
Benchmarks are available at https://github.com/kstenerud/JSONCompare


### It's Simple!

There are two files to add to your project: *KSJSON.h* and *KSJSON.m*.

There are two API calls: *serializeObject* and *deserializeString*. That's it.

No extra dependencies. No special include paths. No extra linker options.
No pollution of NSArray and friends with helper categories that might clash
with another library.


### It's Reliable!

KSJSON includes 70 unit tests, which have 90% code coverage.


### It's Clean!

KSJSON compiles cleanly with ALL warnings enabled (including pedantic).


### It's Small!

The armv7 object code for KSJSON weighs in at 42 kilobytes.


### It supports ARC!

KSJSON supports compiling with or without ARC.



Installation
------------

Copy *KSJSON.h* and *KSJSON.m* into your project.



Usage
-----

### Serialize:

    NSError* error;
    id container = [somewhere getContainer];
    NSString* jsonString = [KSJSON serializeObject:container error:&error];

### Deserialize:

    NSError* error;
    NSString* jsonString = [somewhere getJSONString];
    id container = [KSJSON deserializeString:jsonString error:&error];



License
-------

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall remain in place
in the source code.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
