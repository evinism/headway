#!/bin/bash

cd /graph_volume && tar -xvf gtfs.tar

export GTFS_FILES=$(find /graph_volume | grep \.zip | xargs | sed -e 's/ /,/g')

echo "Using GTFS files: \"$GTFS_FILES\""

if [ "$GTFS_FILES" = "" ];
then
  sed -i "/__magic_string_to_be_replaced_with_gtfs_feeds__/d" /graphhopper/config.yaml
else
  sed -i "s^__magic_string_to_be_replaced_with_gtfs_feeds__^$GTFS_FILES^" /graphhopper/config.yaml
fi

java "${@:2}"