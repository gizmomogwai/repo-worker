/++
 + Copyright: Copyright © 2016, Christian Köstlin
 + Authors: Christian Koestlin, Christian Köstlin
 + License: MIT
 +/

import argparse.api.cli : CLI;
import worker : worker_;
import worker.arguments : Arguments;

mixin CLI!(Arguments).main!((arguments) { return worker_(arguments); });
