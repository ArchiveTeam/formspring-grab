dofile("urlcode.lua")
dofile("table_show.lua")
JSON = (loadfile "JSON.lua")()

local load_json_file = function(file)
  if file then
    local f = io.open(file)
    local data = f:read("*all")
    f:close()
    local err, obj = pcall(function(d) return JSON:decode(d) end, data)
    if err == true then
      -- no error
      return obj
    else
      io.stdout:write("\nJSON response could not be decoded.\n")
      io.stdout:flush()
      return nil
    end
  else
    return nil
  end
end

local read_file = function(file)
  local f = io.open(file)
  local data = f:read("*all")
  f:close()
  return data
end

local escape_lua_pattern
do
  local matches =
  {
    ["^"] = "%^";
    ["$"] = "%$";
    ["("] = "%(";
    [")"] = "%)";
    ["%"] = "%%";
    ["."] = "%.";
    ["["] = "%[";
    ["]"] = "%]";
    ["*"] = "%*";
    ["+"] = "%+";
    ["-"] = "%-";
    ["?"] = "%?";
    ["\0"] = "%z";
  }

  escape_lua_pattern = function(s)
    return (s:gsub(".", matches))
  end
end


local username_count = 0

local write_usernames = function(usernames)
  local filename = os.getenv("USER_DATA_FILENAME")
  if filename then
    local n = 0
    local f = io.open(filename, "w")
    for username, v in pairs(usernames) do
      f:write(username.."\n")
      n = n + 1
    end
    f:close()
    username_count = n
  end
end

local discover_formspring_urls = function(urls, usernames, username, html)
  if not html then
    return
  end

  if username then
    local escaped_username = escape_lua_pattern(username)
    -- questions for this user (guess)
    for url in string.gmatch(html, "href=\"(http://www%.formspring%.me/"..escaped_username.."/q/[0-9]+)\"") do
      table.insert(urls, { url=(url), link_expect_html=1 })
    end
  end

  -- general questions answered by this user (guess)
  for url in string.gmatch(html, "href=\"(http://www%.formspring%.me/r/[^/]+/[0-9]+)") do
    table.insert(urls, { url=(url), link_expect_html=1 })
    table.insert(urls, { url=(url.."?switch=hidden"), link_expect_html=1 })
    table.insert(urls, { url=(url.."/top"), link_expect_html=1 })
    table.insert(urls, { url=(url.."/top?switch=hidden"), link_expect_html=1 })
  end

  -- smile popups
  for answer_id in string.gmatch(html, "class=\"smile_container\" data%-joker%-id=\"([0-9]+)\"") do
    table.insert(urls, { url=("http://www.formspring.me/smile/getAccountsForAnswer?answer_id="..answer_id.."&start=0&ajax=1") })
    table.insert(urls, { url=("http://www.formspring.me/comments/get/"..answer_id.."?ajax=1") })
  end

  -- images
  for url in string.gmatch(html, "<img src=\"(http://[^\"]+)\"") do
    table.insert(urls, { url=url })
  end
  for url in string.gmatch(html, "href=\"(http://files%-cdn%.formspring%.me/[^\"]+)\"") do
    table.insert(urls, { url=url })
  end

  -- user link with hovercard
  local found_new_username = false
  for new_username in string.gmatch(html, "<a href=\"http://www%.formspring%.me/([a-zA-Z0-9]+)\" class=\"[^\"]*hovercard") do
    if not usernames[new_username] then
      usernames[new_username] = true
      found_new_username = true
    end
  end
  if found_new_username then
    write_usernames(usernames)
  end
end


local url_count = 0
local usernames = {}

wget.callbacks.get_urls = function(file, url, is_css, iri)
  -- progress message
  url_count = url_count + 1
  if url_count % 10 == 0 then
    io.stdout:write("\r - Downloaded "..url_count.." URLs, found "..username_count.." usernames")
    io.stdout:flush()
  end

  local urls = {}

  -- MAIN PROFILE PAGE
  local username = string.match(url, "^http://www%.formspring%.me/([a-zA-Z0-9]+)$")
  if username then
    local html = read_file(file)

    -- user profile
    table.insert(urls, { url=("http://formspring.me/"..username), link_expect_html=1 })
    table.insert(urls, { url=("http://www.formspring.me/profile/hovercard/"..username.."?ajax=1") })

    -- questions, smiles, pictures, following, followers
    table.insert(urls, { url=("http://www.formspring.me/"..username.."/questions"), link_expect_html=1 })
    table.insert(urls, { url=("http://www.formspring.me/"..username.."/smiles"), link_expect_html=1 })
    table.insert(urls, { url=("http://www.formspring.me/"..username.."/pictures"), link_expect_html=1 })
    table.insert(urls, { url=("http://www.formspring.me/"..username.."/following"), link_expect_html=1 })
    table.insert(urls, { url=("http://www.formspring.me/"..username.."/followers"), link_expect_html=1 })

    -- paginate responses, smiles, questions
    -- Formspring uses POST, but GET works too
    table.insert(urls, { url=("http://www.formspring.me/profile/moreQuestions/"..username.."?ajax=1&start=0") })
    table.insert(urls, { url=("http://www.formspring.me/profile/moreQuestions/"..username.."?ajax=1&smiles=true&start=0") })
    table.insert(urls, { url=("http://www.formspring.me/profile/moreQuestions/"..username.."?ajax=1&questions=true&start=0") })

    discover_formspring_urls(urls, usernames, username, html)
  end

  -- RESPONSES, SMILES, QUESTIONS (pagination)
  local username, item_type = string.match(url, "^http://www%.formspring%.me/profile/moreQuestions/([a-zA-Z0-9]+)%?ajax=1(.*)&start=[0-9]+$")
  if username and item_type then
    -- ajax pagination of responses, smiles, questions
    local data = load_json_file(file)
    if data and data["questions"] then
      discover_formspring_urls(urls, usernames, username, data["questions"])
    end

    -- another page?
    if data and data["count"] and data["count"] >= 20 then
      -- find final question ID
      local last_question_id = nil
      for question_id in string.gmatch(data["questions"], "<li class=\"question[^>]+rel=\"([0-9]+)\"") do
        last_question_id = question_id
      end

      if last_question_id then
        table.insert(urls, { url=("http://www.formspring.me/profile/moreQuestions/"..username.."?ajax=1"..item_type.."&start="..last_question_id) })
      end
    end
  end

  -- PUBLIC QUESTIONS
  local username = string.match(url, "^http://www%.formspring%.me/([a-zA-Z0-9]+)/questions$")
  if username then
    local html = read_file(file)
    discover_formspring_urls(urls, usernames, username, html)
  end

  -- PUBLIC SMILES
  local username = string.match(url, "^http://www%.formspring%.me/([a-zA-Z0-9]+)/smiles$")
  if username then
    local html = read_file(file)
    discover_formspring_urls(urls, usernames, username, html)
  end

  -- PUBLIC QUESTION
  local base_url = string.match(url, "^(http://www%.formspring%.me/r/[^/]+/[0-9]+)")
  if base_url then
    local html = read_file(file)
    discover_formspring_urls(urls, usernames, nil, html)

    -- find final response ID
    local last_response_id = nil
    for response_id in string.gmatch(html, "<li class=\"question[^>]+rel=\"([0-9]+)\"") do
      last_response_id = response_id
    end

    -- another page?
    if last_response_id then
      table.insert(urls, { url=(base_url.."?max_id="..last_response_id), link_expect_html=1 })
    end
  end

  -- USER QUESTION
  local username = string.match(url, "^http://www%.formspring%.me/([a-zA-Z0-9]+)/q/[0-9]+")
  if username then
    local html = read_file(file)
    discover_formspring_urls(urls, usernames, username, html)
  end

  -- FOLLOWING, FOLLOWERS
  local username, item_type = string.match(url, "^http://www%.formspring%.me/([a-zA-Z0-9]+)/(follow[ersing]+)$")
  if username and item_type then
    -- followers, following page
    local html = read_file(file)
    discover_formspring_urls(urls, usernames, username, html)

    -- another page?
    local next_item = string.match(html, "data%-event=\"paginate\" data%-container=\"#userlist\" data%-start=\"([0-9]+)\"")
    if next_item then
      table.insert(urls, { url=("http://www.formspring.me/profile/morePeople/"..username.."/"..item_type.."?ajax=1&start="..next_item.."&limit=15") })
    end
  end

  -- FOLLOWING, FOLLOWERS (pagination)
  local username, item_type = string.match(url, "^http://www%.formspring%.me/profile/morePeople/([a-zA-Z0-9]+)/(follow[ersing]+)%?ajax=1&start=[0-9]+&limit=15$")
  if username and item_type then
    -- ajax pagination
    local data = load_json_file(file)
    if data and data["content"] then
      discover_formspring_urls(urls, usernames, username, data["content"])
    end

    -- another page?
    if data and data["next"] then
      table.insert(urls, { url=("http://www.formspring.me/profile/morePeople/"..username.."/"..item_type.."?ajax=1&start="..data["next"].."&limit=15") })
    end
  end

  -- PICTURES
  local username = string.match(url, "^http://www%.formspring%.me/([a-zA-Z0-9]+)/pictures$")
  if username then
    local html = read_file(file)
    discover_formspring_urls(urls, usernames, username, html)

    -- pictures
    local escaped_username = escape_lua_pattern(username)
    for url in string.gmatch(html, "href=\"(http://www%.formspring%.me/"..escaped_username.."/picture/[0-9]+)\"") do
      table.insert(urls, { url=url, link_expect_html=1 })
    end
  end

  -- PICTURE
  local username = string.match(url, "^http://www%.formspring%.me/([a-zA-Z0-9]+)/picture/[0-9]+$")
  if username then
    local html = read_file(file)
    discover_formspring_urls(urls, usernames, username, html)

    -- next, previous pictures
    local escaped_username = escape_lua_pattern(username)
    for url in string.gmatch(html, "href=\"(http://www%.formspring%.me/"..escaped_username.."/picture/[0-9]+)\"") do
      table.insert(urls, { url=url, link_expect_html=1 })
    end
  end

  -- ANSWER: SMILES (pagination)
  local answer_id = string.match(url, "^http://www%.formspring%.me/smile/getAccountsForAnswer%?answer_id=([0-9]+)&")
  if answer_id then
    -- ajax pagination
    local data = load_json_file(file)
    local found_new_username = false

    -- users
    local last_result_id = nil
    if data and data["_output"] then
      for result_id, user in string.gmatch(data["_output"], "<li[^>]+id=\"([0-9]+)\">[^<]+<div class=\"profilePic[^\"]*\">[^<]+<a href=\"http://www%.formspring%.me/([a-zA-Z0-9]+)\"") do
        last_result_id = result_id
        if not usernames[user] then
          usernames[user] = true
          found_new_username = true
        end
      end

      -- images
      for url in string.gmatch(data["_output"], "<img src=\"(http://[^\"]+)\"") do
        table.insert(urls, { url=url })
      end

      -- smiles pagination doesn't work
      -- another page?
      -- if data["has_more"] and last_result_id then
      --   table.insert(urls, { url=("http://www.formspring.me/smile/getAccountsForAnswer?answer_id="..answer_id.."&start="..last_result_id.."&ajax=1") })
      -- end
    end

    if found_new_username then
      write_usernames(usernames)
    end
  end

  -- ANSWER: COMMENTS (pagination)
  local answer_id = string.match(url, "^http://www%.formspring%.me/comments/get/([0-9]+)")
  if answer_id then
    -- ajax pagination
    local data = load_json_file(file)
    local found_new_username = false

    if data["comments"] then
      -- each comment
      for i, comment in ipairs(data["comments"]) do
        if comment["user"] then
          if not usernames[comment["user"]["username"]] then
            usernames[comment["user"]["username"]] = true
            found_new_username = true
          end
          table.insert(urls, { url=comment["user"]["photo"] })
        end
      end
    end

    -- another page?
    if data["has_more"] and #data["comments"] > 0 then
      local next_id = data["comments"][#data["comments"]]["id"]
      table.insert(urls, { url=("http://www.formspring.me/comments/get/"..answer_id.."?ajax=1&max_id="..next_id) })
    end

    if found_new_username then
      write_usernames(usernames)
    end
  end

--if #urls > 0 then
--  print(table.show(urls))
--end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  if http_stat.statcode == 200 and http_stat.len == 0 and url.host == "www.formspring.me" then
    -- try again
    io.stdout:write("\nReceived empy response. Waiting for 30 seconds to try again...\n")
    io.stdout:flush()
    os.execute("sleep 30")
    return wget.actions.CONTINUE
  elseif http_stat.statcode == 500 and url.host == "www.formspring.me" then
    -- try again
    io.stdout:write("\nReceived error 500 response. Waiting for 30 seconds to try again...\n")
    io.stdout:flush()
    os.execute("sleep 30")
    return wget.actions.CONTINUE
  else
    return wget.actions.NOTHING
  end
end

