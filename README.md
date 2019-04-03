Bubula² Flumen
==============

This is the source code of [Bubula² Flumen](http://flumen.bubula2.com)
(please notice that the link is dead most of the time) by Daniel
Lundsgaard Skovenborg, <waldeinburg@bubula2.com>.

It's a primitive webserver basically consisting of a single shell script
and an image folder. The images are not included in the source tree. To
prevent bots from ruining the site a separate entrance server with a
CAPTCHA challenge is also made, and the two share a lot of code making
the "single shell script" really be three scripts (plus configuration
files).

Please regard this code as a joke or work of art or both. Because it can
only serve one request at a time you can make a DOS attack against it
just by facing against its location and yell ... okay, maybe a little
more effort than that but not much.

See [the Bubula² Flumen page](http://bubula2.com/en/flumen) for details.


## Files

- server:
  - flumen-common.inc.sh: Common library for the server scripts.
  - flumen-entrance-server.sh: Entrance server.
  - flumen-server.sh: The Bubula² Flumen server!
- systemd:
  - flumen.service: Service file for starting the server process.
  - flumen-entrance.service: Service file for starting the entrance
    server.
  - shutdown.service: Service that shuts down the host.
  - shutdown-after-flumen.timer: Timer to ensure that the Raspberry Pi
    is shut down one hour after startup, i.e., before the timer cuts the
    power.
- tools:
  - entrance-log.sh: Tool for reading the entrance server log.
  - flumen-log.sh: Tool for reading the main server log.
- copy-to-rpi.sh: Tool for copying single files to the host lacking scp
  or rsync etc.
- README.md: huh?
- setup-rpi.sh: Install and update script.
- update-images.sh: Generate and upload images from sources.

The following configuration files are not included in the repository and
must be created to use some of the scripts.

- server:
  - config-flumen-common.inc.sh
  - config-flumen-entrance-server.inc.sh
  - config-flumen-server.inc.sh
- config-dev.inc.sh


## Technical details

The script is intended to run on a Raspberry Pi with a small memory
card. This is the reason for the homemade scp- and rsync-like deployment
scripts.

The main server is based on nc (netcat) and will run through the images
in the folder img once and finally show a static page. It is thus
intended to run on a server that is only running for short periods of
time.

It will keep track of IP-adresses and time of visit to force a delay on
when the same IP is allowed to view a new image.

If running as root it will mount a ramfs filesystem on the folder used
for temporary files. Images are preloaded by saving the base64 value in
the temporary folder, thus avoiding reading from the SD card while
running if a RAM disk is mounted.

Using nc also means that it can only serve one request at a time, making
the server appear to be down while serving a request. The entrance
server is therefore based on socat instead of nc to avoid bots making
the server unresponsive. The code allow socat to be replaced by nc and
vice versa by changing a single variable, but the nc code is not
discarded because part of the concept is that the main server is an
impractical hack.


## License

Copyright (c) 2019 Daniel Lundsgaard Skovenborg
<waldeinburg@bubula2.com>

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
