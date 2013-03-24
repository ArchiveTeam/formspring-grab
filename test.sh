#!/bin/bash
http_proxy=localhost:8123 \
USER_DATA_FILENAME=test.users.txt \
./wget-lua-local \
  -nv \
  -o test.log \
  -U "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.22 (KHTML, like Gecko) Chrome/25.0.1364.172 Safari/537.22" \
  --page-requisites \
  --span-hosts \
  --reject-regex="<%|\[" \
  --output-document t.html \
  --truncate-output \
  -e "robots=off" \
  --lua-script formspring.lua \
  --warc-file t4 \
  http://www.formspring.me/C0llide
# http://www.formspring.me/bonwaf/pictures
# http://www.formspring.me/RebySky/q/437280280579964788
# "http://www.formspring.me/comments/get/370690818253553092?ajax=1"

