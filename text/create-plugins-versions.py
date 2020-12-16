#!/usr/bin/env python3
import glob
import hashlib
import os
import re

# recreates plugins_versions.txt
# usage: create-plugins-versions > plugins_versions.txt


#base_url = 'https://raw.githubusercontent.com/mu3r73/mm-mushclient-scripts/master/'
base_url = 'https://raw.githubusercontent.com/MateriaMagicaLLC/mm-mushclient-scripts/master/'


def create_plugins_versions():
  process_plugins('../src', '*.xml')
  process_other('../src', '*.lua')
  process_other('../res', '*.png')
  process_other('../res', '*.db')


def process_plugins(path, pattern):
  for f in sorted(glob.glob(os.path.join(path, pattern)), key=os.path.basename):
    details = find_plugin_details(f)
    details['hash'] = calc_hash(f)
    show_plugin_info(details)


def process_other(path, pattern):
  for f in sorted(glob.glob(os.path.join(path, pattern)), key=os.path.basename):
    details = {
      'name': os.path.basename(f),
      'hash': calc_hash(f),
    }
    show_other_info(details)


def calc_hash(filename, hash_factory = hashlib.md5, chunk_num_blocks = 128):
  h = hash_factory()
  with open(filename, 'rb') as f: 
    while chunk := f.read(chunk_num_blocks * h.block_size): 
      h.update(chunk)
  return h.hexdigest().upper()


def find_plugin_details(filepath):
  re_id = re.compile(r'^[ ]+id=\"([0-9a-f]+)\"$')
  re_begin_updates = re.compile(f"^{re.escape('function plugin_update_aux_url()')}$")
  re_url_dest = re.compile(f'^[ ]+"{re.escape(base_url)}(src|res)\/(.+),(.+)",$')
  re_url = re.compile(f'^[ ]+"{re.escape(base_url)}(src|res)\/(.+)",$')
  re_end_updates = re.compile(r'^end$')

  updates_started = False
  details = {
    'aux_files': []
  }
  with open(filepath, 'r', encoding = 'ISO-8859-1') as f:
    for line in f:
      ids = re_id.findall(line)
      if (ids):
        details['id'] = ids[0] # 1st result
        continue
      
      if (re_begin_updates.findall(line)):
        updates_started = True
        continue
      
      if (not updates_started):
        continue
      
      url_dest_data = re_url_dest.findall(line)
      if (url_dest_data):
        details.get('aux_files').append({
          'name': url_dest_data[0][1], # 1st result, 2nd elem of tuple
          'dest': url_dest_data[0][2], # 1st result, 3rd elem of tuple
        })
        continue
      
      url_data = re_url.findall(line)
      if (url_data):
        details.get('aux_files').append({
          'name': url_data[0][1], # 1st result, 2nd elem of tuple
        })
        continue

      if (re_end_updates.findall(line)):
        updates_started = False
        continue
  
  return details


def show_plugin_info(details):
  res = f'id = {details.get("id")}  hash = {details.get("hash", "nil")}'
  
  aux_files = details.get('aux_files')
  if (aux_files):
    res = res + '  aux_files = {'

    for (i, e) in enumerate(aux_files, start = 1):
      res = res + f"""   [{i}] = {{     name = "{e.get('name')}","""
      
      dest = e.get('dest')
      if (dest):
        res = res + f'     dest = "{dest}",'
      
      res = res + '     },'

    res = res + '   }'

  print(res)


def show_other_info(details):
  res = f'name = {details.get("name")}  hash = {details.get("hash")}'
  
  print(res)



if __name__ == "__main__":
  create_plugins_versions()



# examples:
#
# * no aux files: affects_by_name
# 
# ... no plugin_update_aux_url() function
# 
# output for plugins_versions.txt:
# id = 6010f6bda5ebf2210998613d  hash = <blah>
# 
# 
# * single aux file, no destination: virtual_arrows
# 
# function plugin_update_aux_url()
#   local t = {
#     "https://raw.githubusercontent.com/<blah>/mm-mushclient-scripts/master/res/buttons.png",
#   }
#   return (table.concat(t, ";"))
# end
# 
# output for plugins_versions.txt:
# id = 3c56fcf3317c6230888de0f6  hash = <blah>  aux_files = {   [1] = {     name = "buttons.png",     },   }
# 
#
# * single aux file with destination: MM_GMCP_Mapper
# 
# function plugin_update_aux_url()
#   local t = {
#     "https://raw.githubusercontent.com/<blah>/mm-mushclient-scripts/master/src/mm_mapper.lua,MUSH/lua",
#   }
#   return (table.concat(t, ";"))
# end
# 
# output for plugins_versions.txt:
# id = f973af093e715dece34dc25f  hash = <blah>  aux_files = {   [1] = {     name = "mm_mapper.lua",     dest = "MUSH/lua",     },   }
# 
#
# * several aux files: capture2dworld
# 
# function plugin_update_aux_url()
#   local t = {
#     "https://raw.githubusercontent.com/<blah>/mm-mushclient-scripts/master/res/captures.MCL,MUSH/worlds",
#     "https://raw.githubusercontent.com/<blah>/mm-mushclient-scripts/master/res/announce.mp3,MUSH/sounds",
#   }
#   return (table.concat(t, ";"))
# end
# 
# output for plugins_versions.txt:
# id = b2772cad800b33a6073d9377  hash = <blah>  aux_files = {   [1] = {     name = "captures.MCL",     dest = "MUSH/worlds",     },   [2] = {     name = "announce.mp3",     dest = "MUSH/sounds",     },   }
