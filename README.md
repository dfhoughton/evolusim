Evolusim
========

Evolusim is an evolution simulator written in Coffeescript. It runs in any modern web browser.  It simulates the interactions among things in a rectangular universe, these things being stones and organisms, organisms being plants or animals, and animals being herbivores or carnivores.  Animals dislike stones and have various aversions and attractions to other organisms. Plants absorb a certain amount of energy from their environment with every tick fo the clock. Animals lose a certain amount.

When an organism has enough energy to reproduce, it attempts to find "cradles" for its babies, where a cradle is a spot unoccupied by the wrong sorts of things -- plants, for instance, can place their babies on stones but animals cannot. It places as many babies as it has energy for so long as it can find cradles. When an organism produces a baby it loses as much energy as the baby gains plus a fixed baby cost. An organism will not reproduce unless it can retain some minimum amount of energy after doing so. This minimum amount is a mutable trait.

When an animal consumes another organism it acquires half the energy of the organism consumed.

Animals can "hear" anything within a certain radius of themselves and "see" anything within a larger wedge in front of them. These are the things they react to. What it perceives determines the magnitude and direction of its acceleration.  If they perceive food, their hunger and the energy value of the food factor into the magnitude of their attraction to it. The influence of an item falls off with the square of its distance from the thing influenced.

Animals have a maximum speed determined by their body size. When they hit walls they bounce. The range of an animal's perception and the angle of its vision are mutable traits, as are the magnitude of its reaction to other things and the acceleration constant which determines how rapidly it reacts to something which comes within its field of perception. The direction an animal is facing is determined by its direction of travel plus a certain amount of random "jitter", which is a mutable trait.

Every time an organism reproduces its baby inherits a copy of its genes, perhaps with mutations.  The mutation rate itself is mutable. Every gene has an associated minimum and maximum that limit the range of possible mutations, though these limits are often a function of the present value. The scale of any mutation within this range is itself mutable.

Running Evolusim
----------------

To run Evolusim first clone it from this repository then compile its Coffeescript files like so

````
coffee -c *.coffee
````

At this point if you open the included HTML file in a web browser you will be able to play with the simulator. Please feel free to fork and enhance the simulation. One might add super predators, for instance, or other constraints on perception or movement, or give predators a certain probability of consuming other predators.

Performance
-----------

Coffeescript is not the highest performance language for computation, and Evolusim has to do a lot of computation. It does this all in a single thread between ticks, or generations. I have tried to improve performance by storing all information regarding geometric relationships among things in an array and working with offsets within this array rather than a pool of objects, but this only goes so far. Evolusim will grab of a lot of memory and will use all the CPU cycles on a particular core. Be aware that it's considering the geometric relationships among all the things in the universe that can react to other things. This are A * ( A + N ) / 2 relationships, where A is the number of animals and N the number of non-animals. I've imposed various limits and tried to short-circuit things appropriately, but there's still a noticeable lag when the number of animals gets very high. One could speed things up by writing the simulator directly in javascript, or by editing the generated javascript so that various arrays are not created only to be discarded unused.

License
-------

See included license file.
