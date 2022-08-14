-- primitives for saving to file and loading from file
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
      table.insert(result, line)
    end
  end
  if #result == 0 then
    table.insert(result, '')
  end
  return result
end

function save_to_disk(State)
  local outfile = App.open_for_writing(State.filename)
  if outfile == nil then
    error('failed to write to "'..State.filename..'"')
  end
  for _,line in ipairs(State.lines) do
    outfile:write(line, '\n')
  end
  outfile:close()
end

-- for tests
function load_array(a)
  local result = {}
  local next_line = ipairs(a)
  local i,line,drawing = 0, ''
  while true do
    i,line = next_line(a, i)
    if i == nil then break end
    table.insert(result, line)
  end
  if #result == 0 then
    table.insert(result, '')
  end
  return result
end
