-- primitives for saving to file and loading from file
function file_exists(filename)
  local infile = App.open_for_reading(filename)
  if infile then
    infile:close()
    return true
  else
    return false
  end
end

function load_from_disk(State)
  local infile = App.open_for_reading(State.filename)
  State.lines = load_from_file(infile)
  if infile then infile:close() end
end

function load_from_file(infile)
  local result = {}
  if infile then
    local infile_next_line = infile:lines()  -- works with both Lua files and LÖVE Files (https://www.love2d.org/wiki/File)
    while true do
      local line = infile_next_line()
      if line == nil then break end
      table.insert(result, {data=line})
    end
  end
  if #result == 0 then
    table.insert(result, {data=''})
  end
  return result
end

function save_to_disk(State)
  local outfile = App.open_for_writing(State.filename)
  if not outfile then
    error('failed to write to "'..State.filename..'"')
  end
  for _,line in ipairs(State.lines) do
    outfile:write(line.data)
    outfile:write('\n')
  end
  outfile:close()
end

-- for tests
function load_array(a)
  local result = {}
  local next_line = ipairs(a)
  local i,line = 0, ''
  while true do
    i,line = next_line(a, i)
    if i == nil then break end
    table.insert(result, {data=line})
  end
  if #result == 0 then
    table.insert(result, {data=''})
  end
  return result
end

function is_absolute_path(path)
  local os_path_separator = package.config:sub(1,1)
  if os_path_separator == '/' then
    -- POSIX systems permit backslashes in filenames
    return path:sub(1,1) == '/'
  elseif os_path_separator == '\\' then
    if path:sub(2,2) == ':' then return true end  -- DOS drive letter followed by volume separator
    local f = path:sub(1,1)
    return f == '/' or f == '\\'
  else
    error('What OS is this? LÖVE reports that the path separator is "'..os_path_separator..'"')
  end
end

function is_relative_path(path)
  return not is_absolute_path(path)
end
