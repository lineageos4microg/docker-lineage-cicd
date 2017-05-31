#!/bin/sh

mv "$1" $(echo "$1" | sed "s|$2|$3|")
