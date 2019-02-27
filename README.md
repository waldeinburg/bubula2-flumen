# Bubula² Flow

This is the source code of [Bubula² Flow](http://flow.bubula2.com) (please notice that the link is dead most of the time) by Daniel Lundsgaard Skovenborg, <waldeinburg@bubula2.com>.

It's a primitive webserver consisting of a single shell script and an image folder. The images are not included in the source tree.

Please regard this code as a joke or work of art or both. Because it can only serve one request at a time you can make a DOS attack against it just by facing against its location and yell ... okay, maybe a little more effort than that but not much.

See [the Bubula² Flow page](http://flow.bubula2.com/en/flow) for details.


## Technical details

The script is intended to run on a Raspberry Pi.

The server is based on nc (netcat) and will run through the images in the folder img once and finally show a static page. It is thus intended to run on a server that is only running for short periods of time.

It will keep track of IP-adresses and time of visit to force a delay on when the same IP is allowed to view a new image.

If running as root it will mount a ramfs filesystem on the folder used for temporary files. Images are preloaded by saving the base64 value in the temporary folder, thus avoiding reading from the SD card while running if a RAM disk is mounted.


## License

Copyright (c) 2019 Daniel Lundsgaard Skovenborg <waldeinburg@bubula2.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
