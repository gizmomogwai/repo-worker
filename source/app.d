/++
 + Copyright: Copyright © 2016, Christian Köstlin
 + Authors: Christian Koestlin, Christian Köstlin
 + License: MIT
 +/

import argparse;
import worker;

mixin CLI!(worker.Arguments).main!((arguments) {
    import worker : worker_;

    return worker_(arguments);
});
