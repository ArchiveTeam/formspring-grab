formspring-grab
===============

Seesaw script for ArchiveTeam Formspring grabbing.
You'll find this project on the Archive Team Warrior (http://tracker.archiveteam.org/formspring/).


Running without a warrior
-------------------------
The warrior is the easiest and most compatible way to help.

If you really want to run this script outside the warrior, clone this repository and run:

    pip install seesaw
    ./get-wget-lua.sh

then start downloading with:

    run-pipeline pipeline.py YOURNICKNAME

For more options, run:

    run-pipeline --help

Thanks.


Installation problems
---------------------
If `get-wget-lua.sh` fails with an error about GNTLS, you need libgnutls-dev. Under Debian/Ubuntu/Mint, try:

    apt-get install libgnutls-dev

If `get-wget-lua.sh` fails with an error about liblua, you need liblua-dev.  Under debian/ubuntu/mint, try:

    apt-get install liblua5.1-dev
