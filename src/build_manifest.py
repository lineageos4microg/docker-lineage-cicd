#!/usr/bin/env python
#
# Copyright (C) 2019 Nicola Corna <nicola@corna.info>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

from xml.dom import minidom
import xml.etree.ElementTree as ET
import argparse
import sys

try:
    from urllib.request import urlopen, Request
    from urllib.error import HTTPError, URLError
except ImportError:
    from urllib2 import urlopen, Request, HTTPError, URLError

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Build an Android repo manifest')
    parser.add_argument('url', type=str, help='URL of the source manifest')
    parser.add_argument('out', type=str, help='Output path')
    parser.add_argument('--remote', type=str, help='Remote URL')
    parser.add_argument('--remotename', type=str, help='Remote name')

    args = parser.parse_args()

    request = Request(args.url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        source_manifest = urlopen(request).read()
    except (HTTPError, URLError) as e:
        # A mirror that does not (yet) carry this branch is not fatal: the
        # caller may be able to proceed without it, so warn and write an
        # empty manifest instead of aborting the whole build.
        reason = getattr(e, 'code', None) or getattr(e, 'reason', e)
        sys.stderr.write(
            "WARNING: could not fetch manifest %s (%s); "
            "writing empty manifest to %s\n" % (args.url, reason, args.out))
        with open(args.out, "w") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n<manifest>\n</manifest>\n')
        sys.exit(0)

    xmlin = ET.fromstring(source_manifest)
    xmlout = ET.Element("manifest")

    if args.remote:
        ET.SubElement(xmlout, 'remote', attrib={"name": args.remotename,
                                                "fetch": args.remote})

    for child in xmlin:
        if child.tag == "project":
            attributes = {}
            attributes["name"] = child.attrib["name"]

            if "path" in child.attrib:
                attributes["path"] = child.attrib["path"]

            if args.remote:
                attributes["remote"] = args.remotename
            
            if "revision" in child.attrib:
                attributes["revision"] = child.attrib["revision"]

            ET.SubElement(xmlout, 'project', attrib=attributes)

    xmlstr = minidom.parseString(ET.tostring(xmlout)).toprettyxml(indent="  ", encoding="UTF-8")
    with open(args.out, "w") as f:
        f.write(xmlstr.decode('utf-8'))
