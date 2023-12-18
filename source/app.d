/++
 + Copyright: Copyright © 2016, Christian Köstlin
 + Authors: Christian Koestlin, Christian Köstlin
 + License: MIT
 +/

import argparse.api.cli : CLI;
import worker : worker_;
import worker.arguments : Arguments;

struct Basic
{
    // Basic data types are supported:
        // '--name' argument
        string name;

        // '--number' argument
        int number;

        // '--boolean' argument
        bool boolean;

    // Argument can have default value if it's not specified in command line
        // '--unused' argument
        string unused = "some default value";


    // Enums are also supported
        enum Enum { unset, foo, boo }
        // '--choice' argument
        Enum choice;

    // Use array to store multiple values
        // '--array' argument
        int[] array;

    // Callback with no args (flag)
        // '--callback' argument
        void callback() {}

    // Callback with single value
        // '--callback1' argument
        void callback1(string value) { assert(value == "cb-value"); }

    // Callback with zero or more values
        // '--callback2' argument
        void callback2(string[] value) { assert(value == ["cb-v1","cb-v2"]); }
}

mixin CLI!(Arguments).main!((arguments) { return worker_(arguments); });
