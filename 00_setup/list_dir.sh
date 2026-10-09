#!/bin/sh
# Preprocessor for ext_inbound_listing: prints one file name per line.
#
# Oracle passes the external table's location file as $1. We list the
# directory that file sits in, so one script serves any inbound
# directory -- pkg_ingest picks the directory by pointing the location
# at that directory's marker file.
#
# Absolute paths only: the preprocessor runs with an empty PATH.
# Plain ls hides dotfiles, so the .inci_listing marker never lists itself.
/bin/ls -1 "$(/usr/bin/dirname "$1")"
