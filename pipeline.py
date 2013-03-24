# This file defines a seesaw pipeline for the ArchiveTeam Warrior.
# It can also be run standalone:
#
#   pip install seesaw
#   run-pipeline pipeline.py YOURNICKNAME
#
# (or run   run-pipeline --help   for more details)
#
import functools
import os
import os.path
import shutil
import time

from distutils.version import StrictVersion
from tornado.httpclient import AsyncHTTPClient, HTTPRequest

# check the seesaw version before importing any other components
import seesaw
if StrictVersion(seesaw.__version__) < StrictVersion("0.0.12"):
  raise Exception("This pipeline needs seesaw version 0.0.12 or higher.")

from seesaw.project import *
from seesaw.config import *
from seesaw.item import *
from seesaw.task import *
from seesaw.pipeline import *
from seesaw.externalprocess import *
from seesaw.tracker import *
from seesaw.util import find_executable

###########################################################################
# Find a useful Wget+Lua executable.
#
# WGET_LUA will be set to the first path that
# 1. does not crash with --version, and
# 2. prints the required version string
WGET_LUA = find_executable("Wget+Lua",
    "GNU Wget 1.14.lua.20130120-8476",
    [ "./wget-lua",
      "./wget-lua-warrior",
      "./wget-lua-local",
      "../wget-lua",
      "../../wget-lua",
      "/home/warrior/wget-lua",
      "/usr/bin/wget-lua" ])

if not WGET_LUA:
  raise Exception("No usable Wget+Lua found.")


###########################################################################
# The user agent for external requests.
#
# Use this constant in the Wget command line.
USER_AGENT = "Mozilla/5.0 (Windows; U; Windows NT 6.1; en-US) AppleWebKit/533.20.25 (KHTML, like Gecko) Version/5.0.4 Safari/533.20.27"

###########################################################################
# The version number of this pipeline definition.
#
# Update this each time you make a non-cosmetic change.
# It will be added to the WARC files and reported to the tracker.
VERSION = "20130324.03"


###########################################################################
# This section defines project-specific tasks.
#
# Simple tasks (tasks that do not need any concurrency) are based on the
# SimpleTask class and have a process(item) method that is called for
# each item.

class PrepareDirectories(SimpleTask):
  """
  A task that creates temporary directories and initializes filenames.

  It initializes these directories, based on the previously set item_name:
    item["item_dir"] = "%{data_dir}/%{item_name}"
    item["warc_file_base"] = "%{warc_prefix}-%{item_name}-%{timestamp}"

  These attributes are used in the following tasks, e.g., the Wget call.

  * set warc_prefix to the project name.
  * item["data_dir"] is set by the environment: it points to a working
    directory reserved for this item.
  * use item["item_dir"] for temporary files
  """
  def __init__(self, warc_prefix):
    SimpleTask.__init__(self, "PrepareDirectories")
    self.warc_prefix = warc_prefix

  def process(self, item):
    item_name = item["item_name"]
    dirname = "/".join(( item["data_dir"], item_name ))

    if os.path.isdir(dirname):
      shutil.rmtree(dirname)
    os.makedirs(dirname)

    item["item_dir"] = dirname
    item["warc_file_base"] = "%s-%s-%s" % (self.warc_prefix, item_name, time.strftime("%Y%m%d-%H%M%S"))
    item["user_data_txt"] = "%s/formspring-user-%s-%s.txt" % (item["data_dir"], item_name, time.strftime("%Y%m%d-%H%M%S"))

    open("%(item_dir)s/%(warc_file_base)s.warc.gz" % item, "w").close()
    open(item["user_data_txt"], "w").close()


class MoveFiles(SimpleTask):
  """
  After downloading, this task moves the warc file from the
  item["item_dir"] directory to the item["data_dir"], and removes
  the files in the item["item_dir"] directory.
  """
  def __init__(self):
    SimpleTask.__init__(self, "MoveFiles")

  def process(self, item):
    os.rename("%(item_dir)s/%(warc_file_base)s.warc.gz" % item,
              "%(data_dir)s/%(warc_file_base)s.warc.gz" % item)

    shutil.rmtree("%(item_dir)s" % item)




###########################################################################
# Initialize the project.
#
# This will be shown in the warrior management panel. The logo should not
# be too big. The deadline is optional.
project = Project(
  title = "Formspring",
  project_html = """
    <img class="project-logo" alt="Formspring Logo" src="http://archiveteam.org/images/a/a0/Formspring-logo258x62_blue.png" height="50" />
    <h2>Formspring <span class="links"><a href="http://www.formspring.me/">Website</a> &middot;
        <a href="http://tracker.archiveteam.org/formspring/">Leaderboard</a></span></h2>
    <p><i>Formspring</i> is closing.</p>
  """
  , utc_deadline = datetime.datetime(2013,04,15, 23,59,0)
)

###########################################################################
# The ID of the tracker for this warrior (used in URLs below).
TRACKER_ID = "formspring"


###########################################################################
# The pipeline.
#
# Items move through each task on the pipeline.
# Items are dicts, so tasks can set properties and can use properties set
# by earlier tasks and (such as the item["item_name"] property).
#
pipeline = Pipeline(
  # request an item from the tracker (using the universal-tracker protocol)
  # the downloader variable will be set by the warrior environment
  #
  # this task will wait for an item and sets item["item_name"] to the item name
  # before finishing
  GetItemFromTracker("http://tracker.archiveteam.org/%s" % TRACKER_ID, downloader, VERSION),

  # create the directories and initialize the filenames (see above)
  # warc_prefix is the first part of the warc filename
  #
  # this task will set item["item_dir"] and item["warc_file_base"]
  PrepareDirectories(warc_prefix="formspring.me"),

  # execute Wget+Lua
  #
  # the ItemInterpolation() objects are resolved during runtime
  # (when there is an Item with values that can be added to the strings)
  WgetDownload([ WGET_LUA,
      "-U", USER_AGENT,
      "-nv",
      "-o", ItemInterpolation("%(item_dir)s/wget.log"),
      "--no-check-certificate",
      "--output-document", ItemInterpolation("%(item_dir)s/wget.tmp"),
      "--truncate-output",
      "-e", "robots=off",
      "--rotate-dns",
      "--page-requisites",
      "--span-hosts", 
      "--reject-regex", r"<%|\[",
      "--timeout", "60",
      "--tries", "20",
      "--waitretry", "5",
      "--lua-script", "formspring.lua",
      "--warc-file", ItemInterpolation("%(item_dir)s/%(warc_file_base)s"),
      "--warc-header", "operator: Archive Team",
      "--warc-header", "formspring-dld-script-version: " + VERSION,
      "--warc-header", ItemInterpolation("formspring-user: %(item_name)s"),
      ItemInterpolation("http://www.formspring.me/%(item_name)s")
    ],
    env={"USER_DATA_FILENAME": ItemInterpolation("%(user_data_txt)s")},
    max_tries = 2,
    # check this: which Wget exit codes count as a success?
    accept_on_exit_code = [ 0, 4, 6, 8 ],
  ),

  # this will set the item["stats"] string that is sent to the tracker (see below)
  PrepareStatsForTracker(
    # there are a few normal values that need to be sent
    defaults = { "downloader": downloader, "version": VERSION },
    # this is used for the size counter on the tracker:
    # the groups should correspond with the groups set configured on the tracker
    file_groups = {
      # there can be multiple groups with multiple files
      # file sizes are measured per group
      "data": [ ItemInterpolation("%(item_dir)s/%(warc_file_base)s.warc.gz") ]
    }
  ),

  # remove the temporary files, move the warc file from
  # item["item_dir"] to item["data_dir"]
  MoveFiles(),
  
  RsyncUpload(
    target = ConfigInterpolation("tracker.archiveteam.org::formspring-user-lists/%s/", downloader),
    target_source_path = ItemInterpolation("%(data_dir)s/"),
    files = [
      ItemInterpolation("%(user_data_txt)s")
    ]
  ),

  # there can be multiple items in the pipeline, but this wrapper ensures
  # that there is only one item uploading at a time
  #
  # the NumberConfigValue can be changed in the configuration panel
  LimitConcurrent(NumberConfigValue(min=1, max=4, default="1", name="shared:rsync_threads", title="Rsync threads", 
description="The maximum number of concurrent uploads."),
    # this upload task asks the tracker for an upload target
    # this can be HTTP or rsync and can be changed in the tracker admin panel
    UploadWithTracker(
      "http://tracker.archiveteam.org/%s" % TRACKER_ID,
      downloader = downloader,
      version = VERSION,
      # list the files that should be uploaded.
      # this may include directory names.
      # note: HTTP uploads will only upload the first file on this list
      files = [
        ItemInterpolation("%(data_dir)s/%(warc_file_base)s.warc.gz")
      ],
      # the relative path for the rsync command
      # (this defines if the files are uploaded to a subdirectory on the server)
      rsync_target_source_path = ItemInterpolation("%(data_dir)s/"),
      # extra rsync parameters (probably standard)
      rsync_extra_args = [
        "--recursive",
        "--partial",
        "--partial-dir", ".rsync-tmp"
      ]
    ),
  ),

  # if the item passed every task, notify the tracker and report the statistics
  SendDoneToTracker(
    tracker_url = "http://tracker.archiveteam.org/%s" % TRACKER_ID,
    stats = ItemValue("stats")
  )
)
