#!/bin/bash
bin_dir=$(realpath $(dirname "$0"))
cd "$bin_dir"

P='WW-Parse-PDA-Engine'
V='0.12.0'
PV="$P-$V"

rm -rf "/tmp/root/$PV"
mkdir -p "/tmp/root/$PV"
rm -f "$PV"

rsync --archive -v --relative $(<MANIFEST) "/tmp/root/$PV"
chown -R root:root "/tmp/root/$PV"

(cd /tmp/root; tar --gzip -cvf "$bin_dir/$PV.tar.gz" "$PV")

