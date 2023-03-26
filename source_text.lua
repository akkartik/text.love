-- text editor, particularly text drawing, horizontal wrap, vertical scrolling
Text = {}

-- draw a line starting from startpos to screen at y between State.left and State.right
-- return the final y, and position of start of final screen line drawn
function Text.draw(State, line_index, y, startpos, hide_cursor)
  local line = State.lines[line_index]
  local line_cache = State.line_cache[line_index]
  line_cache.starty = y
  line_cache.startpos = startpos
  -- wrap long lines
  local x = State.left
  local pos = 1
  local screen_line_starting_pos = startpos
  Text.compute_fragments(State, line_index)
  local pos = 1
  initialize_color()
  for _, f in ipairs(line_cache.fragments) do
    App.color(Text_color)
    local frag, frag_text = f.data, f.text
    select_color(frag)
    local frag_len = utf8.len(frag)
--?     print('text.draw:', frag, 'at', line_index,pos, 'after', x,y)
    if pos < startpos then
      -- render nothing
--?       print('skipping', frag)
    else
      -- render fragment
      local frag_width = App.width(frag_text)
      if x + frag_width > State.right then
        assert(x > State.left)  -- no overfull lines
        y = y + State.line_height
        if y + State.line_height > App.screen.height then
          return y, screen_line_starting_pos
        end
        screen_line_starting_pos = pos
        x = State.left
      end
      if State.selection1.line then
        local lo, hi = Text.clip_selection(State, line_index, pos, pos+frag_len)
        Text.draw_highlight(State, line, x,y, pos, lo,hi)
      end
      -- Make [[WikiWords]] (single word, all in one screen line) clickable.
      local trimmed_word = rtrim(frag)  -- compute_fragments puts whitespace at the end
      if starts_with(trimmed_word, '[[') and ends_with(trimmed_word, ']]') then
        local filename = trimmed_word:gsub('^..(.*)..$', '%1')
        if source.link_exists(State, filename) then
          local filename_text = App.newText(love.graphics.getFont(), filename)
          button(State, 'link', {x=x+App.width(to_text('[[')), y=y, w=App.width(filename_text), h=State.line_height, color={1,1,1},
            icon = icon.hyperlink_decoration,
            onpress1 = function()
                         source.switch_to_file(filename)
                        end,
          })
        end
      end
      App.screen.draw(frag_text, x,y)
      -- render cursor if necessary
      if line_index == State.cursor1.line then
        if pos <= State.cursor1.pos and pos + frag_len > State.cursor1.pos then
          if State.search_term then
            if State.lines[State.cursor1.line].data:sub(State.cursor1.pos, State.cursor1.pos+utf8.len(State.search_term)-1) == State.search_term then
              local lo_px = Text.draw_highlight(State, line, x,y, pos, State.cursor1.pos, State.cursor1.pos+utf8.len(State.search_term))
              App.color(Text_color)
              love.graphics.print(State.search_term, x+lo_px,y)
            end
          elseif Focus == 'edit' then
            Text.draw_cursor(State, x+Text.x(frag, State.cursor1.pos-pos+1), y)
            App.color(Text_color)
          end
        end
      end
      x = x + frag_width
    end
    pos = pos + frag_len
  end
  if Focus == 'edit' and not hide_cursor and State.search_term == nil then
    if line_index == State.cursor1.line and State.cursor1.pos == pos then
      Text.draw_cursor(State, x, y)
    end
  end
  return y, screen_line_starting_pos
end

function Text.draw_cursor(State, x, y)
  -- blink every 0.5s
  if math.floor(Cursor_time*2)%2 == 0 then
    App.color(Cursor_color)
    love.graphics.rectangle('fill', x,y, 3,State.line_height)
  end
  State.cursor_x = x
  State.cursor_y = y+State.line_height
end

function Text.populate_screen_line_starting_pos(State, line_index)
  local line = State.lines[line_index]
  if line.mode ~= 'text' then return end
  local line_cache = State.line_cache[line_index]
  if line_cache.screen_line_starting_pos then
    return
  end
  -- duplicate some logic from Text.draw
  Text.compute_fragments(State, line_index)
  line_cache.screen_line_starting_pos = {1}
  local x = State.left
  local pos = 1
  for _, f in ipairs(line_cache.fragments) do
    local frag, frag_text = f.data, f.text
    -- render fragment
    local frag_width = App.width(frag_text)
    if x + frag_width > State.right then
      x = State.left
      table.insert(line_cache.screen_line_starting_pos, pos)
    end
    x = x + frag_width
    local frag_len = utf8.len(frag)
    pos = pos + frag_len
  end
end

function Text.compute_fragments(State, line_index)
--?   print('compute_fragments', line_index, 'between', State.left, State.right)
  local line = State.lines[line_index]
  if line.mode ~= 'text' then return end
  local line_cache = State.line_cache[line_index]
  if line_cache.fragments then
    return
  end
  line_cache.fragments = {}
  local x = State.left
  -- try to wrap at word boundaries
  for frag in line.data:gmatch('%S*%s*') do
    local frag_text = App.newText(love.graphics.getFont(), frag)
    local frag_width = App.width(frag_text)
--?     print('x: '..tostring(x)..'; frag_width: '..tostring(frag_width)..'; '..tostring(State.right-x)..'px to go')
    while x + frag_width > State.right do
--?       print(('checking whether to split fragment ^%s$ of width %d when rendering from %d'):format(frag, frag_width, x))
      if (x-State.left) < 0.8 * (State.right-State.left) then
--?         print('splitting')
        -- long word; chop it at some letter
        -- We're not going to reimplement TeX here.
        local bpos = Text.nearest_pos_less_than(frag, State.right - x)
--?         print('bpos', bpos)
        if bpos == 0 then break end  -- avoid infinite loop when window is too narrow
        local boffset = Text.offset(frag, bpos+1)  -- byte _after_ bpos
--?         print('space for '..tostring(bpos)..' graphemes, '..tostring(boffset-1)..' bytes')
        local frag1 = string.sub(frag, 1, boffset-1)
        local frag1_text = App.newText(love.graphics.getFont(), frag1)
        local frag1_width = App.width(frag1_text)
--?         print('extracting ^'..frag1..'$ of width '..tostring(frag1_width)..'px')
        assert(x + frag1_width <= State.right)
        table.insert(line_cache.fragments, {data=frag1, text=frag1_text})
        frag = string.sub(frag, boffset)
        frag_text = App.newText(love.graphics.getFont(), frag)
        frag_width = App.width(frag_text)
      end
      x = State.left  -- new line
    end
    if #frag > 0 then
--?       print('inserting ^'..frag..'$ of width '..tostring(frag_width)..'px')
      table.insert(line_cache.fragments, {data=frag, text=frag_text})
    end
    x = x + frag_width
  end
end

function Text.text_input(State, t)
  if App.mouse_down(1) then return end
  if App.ctrl_down() or App.alt_down() or App.cmd_down() then return end
  local before = snapshot(State, State.cursor1.line)
--?   print(State.screen_top1.line, State.screen_top1.pos, State.cursor1.line, State.cursor1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
  Text.insert_at_cursor(State, t)
  if State.cursor_y > App.screen.height - State.line_height then
    Text.populate_screen_line_starting_pos(State, State.cursor1.line)
    Text.snap_cursor_to_bottom_of_screen(State, State.left, State.right)
  end
  record_undo_event(State, {before=before, after=snapshot(State, State.cursor1.line)})
end

function Text.insert_at_cursor(State, t)
  assert(State.lines[State.cursor1.line].mode == 'text')
  local byte_offset = Text.offset(State.lines[State.cursor1.line].data, State.cursor1.pos)
  State.lines[State.cursor1.line].data = string.sub(State.lines[State.cursor1.line].data, 1, byte_offset-1)..t..string.sub(State.lines[State.cursor1.line].data, byte_offset)
  Text.clear_screen_line_cache(State, State.cursor1.line)
  State.cursor1.pos = State.cursor1.pos+1
end

-- Don't handle any keys here that would trigger text_input above.
function Text.keychord_press(State, chord)
--?   print('chord', chord, State.selection1.line, State.selection1.pos)
  --== shortcuts that mutate text
  if chord == 'return' then
    local before_line = State.cursor1.line
    local before = snapshot(State, before_line)
    Text.insert_return(State)
    State.selection1 = {}
    if State.cursor_y > App.screen.height - State.line_height then
      Text.snap_cursor_to_bottom_of_screen(State, State.left, State.right)
    end
    schedule_save(State)
    record_undo_event(State, {before=before, after=snapshot(State, before_line, State.cursor1.line)})
  elseif chord == 'tab' then
    local before = snapshot(State, State.cursor1.line)
--?     print(State.screen_top1.line, State.screen_top1.pos, State.cursor1.line, State.cursor1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
    Text.insert_at_cursor(State, '\t')
    if State.cursor_y > App.screen.height - State.line_height then
      Text.populate_screen_line_starting_pos(State, State.cursor1.line)
      Text.snap_cursor_to_bottom_of_screen(State, State.left, State.right)
--?       print('=>', State.screen_top1.line, State.screen_top1.pos, State.cursor1.line, State.cursor1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
    end
    schedule_save(State)
    record_undo_event(State, {before=before, after=snapshot(State, State.cursor1.line)})
  elseif chord == 'backspace' then
    if State.selection1.line then
      Text.delete_selection(State, State.left, State.right)
      schedule_save(State)
      return
    end
    local before
    if State.cursor1.pos > 1 then
      before = snapshot(State, State.cursor1.line)
      local byte_start = utf8.offset(State.lines[State.cursor1.line].data, State.cursor1.pos-1)
      local byte_end = utf8.offset(State.lines[State.cursor1.line].data, State.cursor1.pos)
      if byte_start then
        if byte_end then
          State.lines[State.cursor1.line].data = string.sub(State.lines[State.cursor1.line].data, 1, byte_start-1)..string.sub(State.lines[State.cursor1.line].data, byte_end)
        else
          State.lines[State.cursor1.line].data = string.sub(State.lines[State.cursor1.line].data, 1, byte_start-1)
        end
        State.cursor1.pos = State.cursor1.pos-1
      end
    elseif State.cursor1.line > 1 then
      before = snapshot(State, State.cursor1.line-1, State.cursor1.line)
      if State.lines[State.cursor1.line-1].mode == 'drawing' then
        table.remove(State.lines, State.cursor1.line-1)
        table.remove(State.line_cache, State.cursor1.line-1)
      else
        -- join lines
        State.cursor1.pos = utf8.len(State.lines[State.cursor1.line-1].data)+1
        State.lines[State.cursor1.line-1].data = State.lines[State.cursor1.line-1].data..State.lines[State.cursor1.line].data
        table.remove(State.lines, State.cursor1.line)
        table.remove(State.line_cache, State.cursor1.line)
      end
      State.cursor1.line = State.cursor1.line-1
    end
    if State.screen_top1.line > #State.lines then
      Text.populate_screen_line_starting_pos(State, #State.lines)
      local line_cache = State.line_cache[#State.line_cache]
      State.screen_top1 = {line=#State.lines, pos=line_cache.screen_line_starting_pos[#line_cache.screen_line_starting_pos]}
    elseif Text.lt1(State.cursor1, State.screen_top1) then
      State.screen_top1 = {
        line=State.cursor1.line,
        pos=Text.pos_at_start_of_screen_line(State, State.cursor1),
      }
      Text.redraw_all(State)  -- if we're scrolling, reclaim all fragments to avoid memory leaks
    end
    Text.clear_screen_line_cache(State, State.cursor1.line)
    assert(Text.le1(State.screen_top1, State.cursor1))
    schedule_save(State)
    record_undo_event(State, {before=before, after=snapshot(State, State.cursor1.line)})
  elseif chord == 'delete' then
    if State.selection1.line then
      Text.delete_selection(State, State.left, State.right)
      schedule_save(State)
      return
    end
    local before
    if State.cursor1.pos <= utf8.len(State.lines[State.cursor1.line].data) then
      before = snapshot(State, State.cursor1.line)
    else
      before = snapshot(State, State.cursor1.line, State.cursor1.line+1)
    end
    if State.cursor1.pos <= utf8.len(State.lines[State.cursor1.line].data) then
      local byte_start = utf8.offset(State.lines[State.cursor1.line].data, State.cursor1.pos)
      local byte_end = utf8.offset(State.lines[State.cursor1.line].data, State.cursor1.pos+1)
      if byte_start then
        if byte_end then
          State.lines[State.cursor1.line].data = string.sub(State.lines[State.cursor1.line].data, 1, byte_start-1)..string.sub(State.lines[State.cursor1.line].data, byte_end)
        else
          State.lines[State.cursor1.line].data = string.sub(State.lines[State.cursor1.line].data, 1, byte_start-1)
        end
        -- no change to State.cursor1.pos
      end
    elseif State.cursor1.line < #State.lines then
      if State.lines[State.cursor1.line+1].mode == 'text' then
        -- join lines
        State.lines[State.cursor1.line].data = State.lines[State.cursor1.line].data..State.lines[State.cursor1.line+1].data
      end
      table.remove(State.lines, State.cursor1.line+1)
      table.remove(State.line_cache, State.cursor1.line+1)
    end
    Text.clear_screen_line_cache(State, State.cursor1.line)
    schedule_save(State)
    record_undo_event(State, {before=before, after=snapshot(State, State.cursor1.line)})
  --== shortcuts that move the cursor
  elseif chord == 'left' then
    Text.left(State)
    State.selection1 = {}
  elseif chord == 'right' then
    Text.right(State)
    State.selection1 = {}
  elseif chord == 'S-left' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.left(State)
  elseif chord == 'S-right' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.right(State)
  -- C- hotkeys reserved for drawings, so we'll use M-
  elseif chord == 'M-left' then
    Text.word_left(State)
    State.selection1 = {}
  elseif chord == 'M-right' then
    Text.word_right(State)
    State.selection1 = {}
  elseif chord == 'M-S-left' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.word_left(State)
  elseif chord == 'M-S-right' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.word_right(State)
  elseif chord == 'home' then
    Text.start_of_line(State)
    State.selection1 = {}
  elseif chord == 'end' then
    Text.end_of_line(State)
    State.selection1 = {}
  elseif chord == 'S-home' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.start_of_line(State)
  elseif chord == 'S-end' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.end_of_line(State)
  elseif chord == 'up' then
    Text.up(State)
    State.selection1 = {}
  elseif chord == 'down' then
    Text.down(State)
    State.selection1 = {}
  elseif chord == 'S-up' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.up(State)
  elseif chord == 'S-down' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.down(State)
  elseif chord == 'pageup' then
    Text.pageup(State)
    State.selection1 = {}
  elseif chord == 'pagedown' then
    Text.pagedown(State)
    State.selection1 = {}
  elseif chord == 'S-pageup' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.pageup(State)
  elseif chord == 'S-pagedown' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.pagedown(State)
  end
end

function Text.insert_return(State)
  local byte_offset = Text.offset(State.lines[State.cursor1.line].data, State.cursor1.pos)
  table.insert(State.lines, State.cursor1.line+1, {mode='text', data=string.sub(State.lines[State.cursor1.line].data, byte_offset)})
  table.insert(State.line_cache, State.cursor1.line+1, {})
  State.lines[State.cursor1.line].data = string.sub(State.lines[State.cursor1.line].data, 1, byte_offset-1)
  Text.clear_screen_line_cache(State, State.cursor1.line)
  State.cursor1 = {line=State.cursor1.line+1, pos=1}
end

function Text.pageup(State)
--?   print('pageup')
  -- duplicate some logic from love.draw
  local top2 = Text.to2(State, State.screen_top1)
--?   print(App.screen.height)
  local y = App.screen.height - State.line_height
  while y >= State.top do
--?     print(y, top2.line, top2.screen_line, top2.screen_pos)
    if State.screen_top1.line == 1 and State.screen_top1.pos == 1 then break end
    if State.lines[State.screen_top1.line].mode == 'text' then
      y = y - State.line_height
    elseif State.lines[State.screen_top1.line].mode == 'drawing' then
      y = y - Drawing_padding_height - Drawing.pixels(State.lines[State.screen_top1.line].h, State.width)
    end
    top2 = Text.previous_screen_line(State, top2)
  end
  State.screen_top1 = Text.to1(State, top2)
  State.cursor1 = {line=State.screen_top1.line, pos=State.screen_top1.pos}
  Text.move_cursor_down_to_next_text_line_while_scrolling_again_if_necessary(State)
--?   print(State.cursor1.line, State.cursor1.pos, State.screen_top1.line, State.screen_top1.pos)
--?   print('pageup end')
end

function Text.pagedown(State)
--?   print('pagedown')
  -- If a line/paragraph gets to a page boundary, I often want to scroll
  -- before I get to the bottom.
  -- However, only do this if it makes forward progress.
  local bot2 = Text.to2(State, State.screen_bottom1)
  if bot2.screen_line > 1 then
    bot2.screen_line = math.max(bot2.screen_line-10, 1)
  end
  local new_top1 = Text.to1(State, bot2)
  if Text.lt1(State.screen_top1, new_top1) then
    State.screen_top1 = new_top1
  else
    State.screen_top1 = {line=State.screen_bottom1.line, pos=State.screen_bottom1.pos}
  end
--?   print('setting top to', State.screen_top1.line, State.screen_top1.pos)
  State.cursor1 = {line=State.screen_top1.line, pos=State.screen_top1.pos}
  Text.move_cursor_down_to_next_text_line_while_scrolling_again_if_necessary(State)
--?   print('top now', State.screen_top1.line)
  Text.redraw_all(State)  -- if we're scrolling, reclaim all fragments to avoid memory leaks
--?   print('pagedown end')
end

function Text.up(State)
  assert(State.lines[State.cursor1.line].mode == 'text')
--?   print('up', State.cursor1.line, State.cursor1.pos, State.screen_top1.line, State.screen_top1.pos)
  local screen_line_starting_pos, screen_line_index = Text.pos_at_start_of_screen_line(State, State.cursor1)
  if screen_line_starting_pos == 1 then
--?     print('cursor is at first screen line of its line')
    -- line is done; skip to previous text line
    local new_cursor_line = State.cursor1.line
    while new_cursor_line > 1 do
      new_cursor_line = new_cursor_line-1
      if State.lines[new_cursor_line].mode == 'text' then
--?         print('found previous text line')
        State.cursor1 = {line=new_cursor_line, pos=nil}
        Text.populate_screen_line_starting_pos(State, State.cursor1.line)
        -- previous text line found, pick its final screen line
--?         print('has multiple screen lines')
        local screen_line_starting_pos = State.line_cache[State.cursor1.line].screen_line_starting_pos
--?         print(#screen_line_starting_pos)
        screen_line_starting_pos = screen_line_starting_pos[#screen_line_starting_pos]
        local screen_line_starting_byte_offset = Text.offset(State.lines[State.cursor1.line].data, screen_line_starting_pos)
        local s = string.sub(State.lines[State.cursor1.line].data, screen_line_starting_byte_offset)
        State.cursor1.pos = screen_line_starting_pos + Text.nearest_cursor_pos(s, State.cursor_x, State.left) - 1
        break
      end
    end
  else
    -- move up one screen line in current line
    assert(screen_line_index > 1)
    local new_screen_line_starting_pos = State.line_cache[State.cursor1.line].screen_line_starting_pos[screen_line_index-1]
    local new_screen_line_starting_byte_offset = Text.offset(State.lines[State.cursor1.line].data, new_screen_line_starting_pos)
    local s = string.sub(State.lines[State.cursor1.line].data, new_screen_line_starting_byte_offset)
    State.cursor1.pos = new_screen_line_starting_pos + Text.nearest_cursor_pos(s, State.cursor_x, State.left) - 1
--?     print('cursor pos is now '..tostring(State.cursor1.pos))
  end
  if Text.lt1(State.cursor1, State.screen_top1) then
    State.screen_top1 = {
      line=State.cursor1.line,
      pos=Text.pos_at_start_of_screen_line(State, State.cursor1),
    }
    Text.redraw_all(State)  -- if we're scrolling, reclaim all fragments to avoid memory leaks
  end
end

function Text.down(State)
  assert(State.lines[State.cursor1.line].mode == 'text')
--?   print('down', State.cursor1.line, State.cursor1.pos, State.screen_top1.line, State.screen_top1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
  if Text.cursor_at_final_screen_line(State) then
    -- line is done, skip to next text line
--?     print('cursor at final screen line of its line')
    local new_cursor_line = State.cursor1.line
    while new_cursor_line < #State.lines do
      new_cursor_line = new_cursor_line+1
      if State.lines[new_cursor_line].mode == 'text' then
        State.cursor1 = {
          line = new_cursor_line,
          pos = Text.nearest_cursor_pos(State.lines[new_cursor_line].data, State.cursor_x, State.left),
        }
--?         print(State.cursor1.pos)
        break
      end
    end
    if State.cursor1.line > State.screen_bottom1.line then
--?       print('screen top before:', State.screen_top1.line, State.screen_top1.pos)
--?       print('scroll up preserving cursor')
      Text.snap_cursor_to_bottom_of_screen(State)
--?       print('screen top after:', State.screen_top1.line, State.screen_top1.pos)
    end
  else
    -- move down one screen line in current line
    local scroll_down = Text.le1(State.screen_bottom1, State.cursor1)
--?     print('cursor is NOT at final screen line of its line')
    local screen_line_starting_pos, screen_line_index = Text.pos_at_start_of_screen_line(State, State.cursor1)
    Text.populate_screen_line_starting_pos(State, State.cursor1.line)
    local new_screen_line_starting_pos = State.line_cache[State.cursor1.line].screen_line_starting_pos[screen_line_index+1]
--?     print('switching pos of screen line at cursor from '..tostring(screen_line_starting_pos)..' to '..tostring(new_screen_line_starting_pos))
    local new_screen_line_starting_byte_offset = Text.offset(State.lines[State.cursor1.line].data, new_screen_line_starting_pos)
    local s = string.sub(State.lines[State.cursor1.line].data, new_screen_line_starting_byte_offset)
    State.cursor1.pos = new_screen_line_starting_pos + Text.nearest_cursor_pos(s, State.cursor_x, State.left) - 1
--?     print('cursor pos is now', State.cursor1.line, State.cursor1.pos)
    if scroll_down then
--?       print('scroll up preserving cursor')
      Text.snap_cursor_to_bottom_of_screen(State)
--?       print('screen top after:', State.screen_top1.line, State.screen_top1.pos)
    end
  end
--?   print('=>', State.cursor1.line, State.cursor1.pos, State.screen_top1.line, State.screen_top1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
end

function Text.start_of_line(State)
  State.cursor1.pos = 1
  if Text.lt1(State.cursor1, State.screen_top1) then
    State.screen_top1 = {line=State.cursor1.line, pos=State.cursor1.pos}  -- copy
  end
end

function Text.end_of_line(State)
  State.cursor1.pos = utf8.len(State.lines[State.cursor1.line].data) + 1
  if Text.cursor_out_of_screen(State) then
    Text.snap_cursor_to_bottom_of_screen(State)
  end
end

function Text.word_left(State)
  -- skip some whitespace
  while true do
    if State.cursor1.pos == 1 then
      break
    end
    if Text.match(State.lines[State.cursor1.line].data, State.cursor1.pos-1, '%S') then
      break
    end
    Text.left(State)
  end
  -- skip some non-whitespace
  while true do
    Text.left(State)
    if State.cursor1.pos == 1 then
      break
    end
    assert(State.cursor1.pos > 1)
    if Text.match(State.lines[State.cursor1.line].data, State.cursor1.pos-1, '%s') then
      break
    end
  end
end

function Text.word_right(State)
  -- skip some whitespace
  while true do
    if State.cursor1.pos > utf8.len(State.lines[State.cursor1.line].data) then
      break
    end
    if Text.match(State.lines[State.cursor1.line].data, State.cursor1.pos, '%S') then
      break
    end
    Text.right_without_scroll(State)
  end
  while true do
    Text.right_without_scroll(State)
    if State.cursor1.pos > utf8.len(State.lines[State.cursor1.line].data) then
      break
    end
    if Text.match(State.lines[State.cursor1.line].data, State.cursor1.pos, '%s') then
      break
    end
  end
  if Text.cursor_out_of_screen(State) then
    Text.snap_cursor_to_bottom_of_screen(State)
  end
end

function Text.match(s, pos, pat)
  local start_offset = Text.offset(s, pos)
  assert(start_offset)
  local end_offset = Text.offset(s, pos+1)
  assert(end_offset > start_offset)
  local curr = s:sub(start_offset, end_offset-1)
  return curr:match(pat)
end

function Text.left(State)
  assert(State.lines[State.cursor1.line].mode == 'text')
  if State.cursor1.pos > 1 then
    State.cursor1.pos = State.cursor1.pos-1
  else
    local new_cursor_line = State.cursor1.line
    while new_cursor_line > 1 do
      new_cursor_line = new_cursor_line-1
      if State.lines[new_cursor_line].mode == 'text' then
        State.cursor1 = {
          line = new_cursor_line,
          pos = utf8.len(State.lines[new_cursor_line].data) + 1,
        }
        break
      end
    end
  end
  if Text.lt1(State.cursor1, State.screen_top1) then
    State.screen_top1 = {
      line=State.cursor1.line,
      pos=Text.pos_at_start_of_screen_line(State, State.cursor1),
    }
    Text.redraw_all(State)  -- if we're scrolling, reclaim all fragments to avoid memory leaks
  end
end

function Text.right(State)
  Text.right_without_scroll(State)
  if Text.cursor_out_of_screen(State) then
    Text.snap_cursor_to_bottom_of_screen(State)
  end
end

function Text.right_without_scroll(State)
  assert(State.lines[State.cursor1.line].mode == 'text')
  if State.cursor1.pos <= utf8.len(State.lines[State.cursor1.line].data) then
    State.cursor1.pos = State.cursor1.pos+1
  else
    local new_cursor_line = State.cursor1.line
    while new_cursor_line <= #State.lines-1 do
      new_cursor_line = new_cursor_line+1
      if State.lines[new_cursor_line].mode == 'text' then
        State.cursor1 = {line=new_cursor_line, pos=1}
        break
      end
    end
  end
end

function Text.pos_at_start_of_screen_line(State, loc1)
  Text.populate_screen_line_starting_pos(State, loc1.line)
  local line_cache = State.line_cache[loc1.line]
  for i=#line_cache.screen_line_starting_pos,1,-1 do
    local spos = line_cache.screen_line_starting_pos[i]
    if spos <= loc1.pos then
      return spos,i
    end
  end
  assert(false)
end

function Text.cursor_at_final_screen_line(State)
  Text.populate_screen_line_starting_pos(State, State.cursor1.line)
  local screen_lines = State.line_cache[State.cursor1.line].screen_line_starting_pos
--?   print(screen_lines[#screen_lines], State.cursor1.pos)
  return screen_lines[#screen_lines] <= State.cursor1.pos
end

function Text.move_cursor_down_to_next_text_line_while_scrolling_again_if_necessary(State)
  local y = State.top
  while State.cursor1.line <= #State.lines do
    if State.lines[State.cursor1.line].mode == 'text' then
      break
    end
--?     print('cursor skips', State.cursor1.line)
    y = y + Drawing_padding_height + Drawing.pixels(State.lines[State.cursor1.line].h, State.width)
    State.cursor1.line = State.cursor1.line + 1
  end
  -- hack: insert a text line at bottom of file if necessary
  if State.cursor1.line > #State.lines then
    assert(State.cursor1.line == #State.lines+1)
    table.insert(State.lines, {mode='text', data=''})
    table.insert(State.line_cache, {})
  end
--?   print(y, App.screen.height, App.screen.height-State.line_height)
  if y > App.screen.height - State.line_height then
--?     print('scroll up')
    Text.snap_cursor_to_bottom_of_screen(State)
  end
end

-- should never modify State.cursor1
function Text.snap_cursor_to_bottom_of_screen(State)
--?   print('to2:', State.cursor1.line, State.cursor1.pos)
  local top2 = Text.to2(State, State.cursor1)
--?   print('to2: =>', top2.line, top2.screen_line, top2.screen_pos)
  -- slide to start of screen line
  top2.screen_pos = 1  -- start of screen line
--?   print('snap', State.screen_top1.line, State.screen_top1.pos, State.cursor1.line, State.cursor1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
--?   print('cursor pos '..tostring(State.cursor1.pos)..' is on the #'..tostring(top2.screen_line)..' screen line down')
  local y = App.screen.height - State.line_height
  -- duplicate some logic from love.draw
  while true do
--?     print(y, 'top2:', top2.line, top2.screen_line, top2.screen_pos)
    if top2.line == 1 and top2.screen_line == 1 then break end
    if top2.screen_line > 1 or State.lines[top2.line-1].mode == 'text' then
      local h = State.line_height
      if y - h < State.top then
        break
      end
      y = y - h
    else
      assert(top2.line > 1)
      assert(State.lines[top2.line-1].mode == 'drawing')
      -- We currently can't draw partial drawings, so either skip it entirely
      -- or not at all.
      local h = Drawing_padding_height + Drawing.pixels(State.lines[top2.line-1].h, State.width)
      if y - h < State.top then
        break
      end
--?       print('skipping drawing of height', h)
      y = y - h
    end
    top2 = Text.previous_screen_line(State, top2)
  end
--?   print('top2 finally:', top2.line, top2.screen_line, top2.screen_pos)
  State.screen_top1 = Text.to1(State, top2)
--?   print('top1 finally:', State.screen_top1.line, State.screen_top1.pos)
--?   print('snap =>', State.screen_top1.line, State.screen_top1.pos, State.cursor1.line, State.cursor1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
  Text.redraw_all(State)  -- if we're scrolling, reclaim all fragments to avoid memory leaks
end

function Text.in_line(State, line_index, x,y)
  local line = State.lines[line_index]
  local line_cache = State.line_cache[line_index]
  if line_cache.starty == nil then return false end  -- outside current page
  if y < line_cache.starty then return false end
  Text.populate_screen_line_starting_pos(State, line_index)
  return y < line_cache.starty + State.line_height*(#line_cache.screen_line_starting_pos - Text.screen_line_index(line_cache.screen_line_starting_pos, line_cache.startpos) + 1)
end

-- convert mx,my in pixels to schema-1 coordinates
function Text.to_pos_on_line(State, line_index, mx, my)
  local line = State.lines[line_index]
  local line_cache = State.line_cache[line_index]
  assert(my >= line_cache.starty)
  -- duplicate some logic from Text.draw
  local y = line_cache.starty
  local start_screen_line_index = Text.screen_line_index(line_cache.screen_line_starting_pos, line_cache.startpos)
  for screen_line_index = start_screen_line_index,#line_cache.screen_line_starting_pos do
    local screen_line_starting_pos = line_cache.screen_line_starting_pos[screen_line_index]
    local screen_line_starting_byte_offset = Text.offset(line.data, screen_line_starting_pos)
--?     print('iter', y, screen_line_index, screen_line_starting_pos, string.sub(line.data, screen_line_starting_byte_offset))
    local nexty = y + State.line_height
    if my < nexty then
      -- On all wrapped screen lines but the final one, clicks past end of
      -- line position cursor on final character of screen line.
      -- (The final screen line positions past end of screen line as always.)
      if screen_line_index < #line_cache.screen_line_starting_pos and mx > State.left + Text.screen_line_width(State, line_index, screen_line_index) then
--?         print('past end of non-final line; return')
        return line_cache.screen_line_starting_pos[screen_line_index+1]-1
      end
      local s = string.sub(line.data, screen_line_starting_byte_offset)
--?       print('return', mx, Text.nearest_cursor_pos(s, mx, State.left), '=>', screen_line_starting_pos + Text.nearest_cursor_pos(s, mx, State.left) - 1)
      return screen_line_starting_pos + Text.nearest_cursor_pos(s, mx, State.left) - 1
    end
    y = nexty
  end
  assert(false)
end

function Text.screen_line_width(State, line_index, i)
  local line = State.lines[line_index]
  local line_cache = State.line_cache[line_index]
  local start_pos = line_cache.screen_line_starting_pos[i]
  local start_offset = Text.offset(line.data, start_pos)
  local screen_line
  if i < #line_cache.screen_line_starting_pos then
    local past_end_pos = line_cache.screen_line_starting_pos[i+1]
    local past_end_offset = Text.offset(line.data, past_end_pos)
    screen_line = string.sub(line.data, start_offset, past_end_offset-1)
  else
    screen_line = string.sub(line.data, start_pos)
  end
  local screen_line_text = App.newText(love.graphics.getFont(), screen_line)
  return App.width(screen_line_text)
end

function Text.screen_line_index(screen_line_starting_pos, pos)
  for i = #screen_line_starting_pos,1,-1 do
    if screen_line_starting_pos[i] <= pos then
      return i
    end
  end
end

-- convert x pixel coordinate to pos
-- oblivious to wrapping
-- result: 1 to len+1
function Text.nearest_cursor_pos(line, x, left)
  if x < left then
    return 1
  end
  local len = utf8.len(line)
  local max_x = left+Text.x(line, len+1)
  if x > max_x then
    return len+1
  end
  local leftpos, rightpos = 1, len+1
--?   print('-- nearest', x)
  while true do
--?     print('nearest', x, '^'..line..'$', leftpos, rightpos)
    if leftpos == rightpos then
      return leftpos
    end
    local curr = math.floor((leftpos+rightpos)/2)
    local currxmin = left+Text.x(line, curr)
    local currxmax = left+Text.x(line, curr+1)
--?     print('nearest', x, leftpos, rightpos, curr, currxmin, currxmax)
    if currxmin <= x and x < currxmax then
      if x-currxmin < currxmax-x then
        return curr
      else
        return curr+1
      end
    end
    if leftpos >= rightpos-1 then
      return rightpos
    end
    if currxmin > x then
      rightpos = curr
    else
      leftpos = curr
    end
  end
  assert(false)
end

-- return the nearest index of line (in utf8 code points) which lies entirely
-- within x pixels of the left margin
-- result: 0 to len+1
function Text.nearest_pos_less_than(line, x)
--?   print('', '-- nearest_pos_less_than', line, x)
  local len = utf8.len(line)
  local max_x = Text.x_after(line, len)
  if x > max_x then
    return len+1
  end
  local left, right = 0, len+1
  while true do
    local curr = math.floor((left+right)/2)
    local currxmin = Text.x_after(line, curr+1)
    local currxmax = Text.x_after(line, curr+2)
--?     print('', x, left, right, curr, currxmin, currxmax)
    if currxmin <= x and x < currxmax then
      return curr
    end
    if left >= right-1 then
      return left
    end
    if currxmin > x then
      right = curr
    else
      left = curr
    end
  end
  assert(false)
end

function Text.x_after(s, pos)
  local offset = Text.offset(s, math.min(pos+1, #s+1))
  local s_before = s:sub(1, offset-1)
--?   print('^'..s_before..'$')
  local text_before = App.newText(love.graphics.getFont(), s_before)
  return App.width(text_before)
end

function Text.x(s, pos)
  local offset = Text.offset(s, pos)
  local s_before = s:sub(1, offset-1)
  local text_before = App.newText(love.graphics.getFont(), s_before)
  return App.width(text_before)
end

function Text.to2(State, loc1)
  if State.lines[loc1.line].mode == 'drawing' then
    return {line=loc1.line, screen_line=1, screen_pos=1}
  end
  local result = {line=loc1.line}
  local line_cache = State.line_cache[loc1.line]
  Text.populate_screen_line_starting_pos(State, loc1.line)
  for i=#line_cache.screen_line_starting_pos,1,-1 do
    local spos = line_cache.screen_line_starting_pos[i]
    if spos <= loc1.pos then
      result.screen_line = i
      result.screen_pos = loc1.pos - spos + 1
      break
    end
  end
  assert(result.screen_pos)
  return result
end

function Text.to1(State, loc2)
  local result = {line=loc2.line, pos=loc2.screen_pos}
  if loc2.screen_line > 1 then
    result.pos = State.line_cache[loc2.line].screen_line_starting_pos[loc2.screen_line] + loc2.screen_pos - 1
  end
  return result
end

function Text.eq1(a, b)
  return a.line == b.line and a.pos == b.pos
end

function Text.lt1(a, b)
  if a.line < b.line then
    return true
  end
  if a.line > b.line then
    return false
  end
  return a.pos < b.pos
end

function Text.le1(a, b)
  if a.line < b.line then
    return true
  end
  if a.line > b.line then
    return false
  end
  return a.pos <= b.pos
end

function Text.offset(s, pos1)
  if pos1 == 1 then return 1 end
  local result = utf8.offset(s, pos1)
  if result == nil then
    print(pos1, #s, s)
  end
  assert(result)
  return result
end

function Text.previous_screen_line(State, loc2)
  if loc2.screen_line > 1 then
    return {line=loc2.line, screen_line=loc2.screen_line-1, screen_pos=1}
  elseif loc2.line == 1 then
    return loc2
  elseif State.lines[loc2.line-1].mode == 'drawing' then
    return {line=loc2.line-1, screen_line=1, screen_pos=1}
  else
    local l = State.lines[loc2.line-1]
    Text.populate_screen_line_starting_pos(State, loc2.line-1)
    return {line=loc2.line-1, screen_line=#State.line_cache[loc2.line-1].screen_line_starting_pos, screen_pos=1}
  end
end

-- resize helper
function Text.tweak_screen_top_and_cursor(State)
  if State.screen_top1.pos == 1 then return end
  Text.populate_screen_line_starting_pos(State, State.screen_top1.line)
  local line = State.lines[State.screen_top1.line]
  local line_cache = State.line_cache[State.screen_top1.line]
  for i=2,#line_cache.screen_line_starting_pos do
    local pos = line_cache.screen_line_starting_pos[i]
    if pos == State.screen_top1.pos then
      break
    end
    if pos > State.screen_top1.pos then
      -- make sure screen top is at start of a screen line
      local prev = line_cache.screen_line_starting_pos[i-1]
      if State.screen_top1.pos - prev < pos - State.screen_top1.pos then
        State.screen_top1.pos = prev
      else
        State.screen_top1.pos = pos
      end
      break
    end
  end
  -- make sure cursor is on screen
  if Text.lt1(State.cursor1, State.screen_top1) then
    State.cursor1 = {line=State.screen_top1.line, pos=State.screen_top1.pos}
  elseif State.cursor1.line >= State.screen_bottom1.line then
--?     print('too low')
    if Text.cursor_out_of_screen(State) then
--?       print('tweak')
      State.cursor1 = {
          line=State.screen_bottom1.line,
          pos=Text.to_pos_on_line(State, State.screen_bottom1.line, State.right-5, App.screen.height-5),
      }
    end
  end
end

-- slightly expensive since it redraws the screen
function Text.cursor_out_of_screen(State)
  App.draw()
  return State.cursor_y == nil
  -- this approach is cheaper and almost works, except on the final screen
  -- where file ends above bottom of screen
--?   local botpos = Text.pos_at_start_of_screen_line(State, State.cursor1)
--?   local botline1 = {line=State.cursor1.line, pos=botpos}
--?   return Text.lt1(State.screen_bottom1, botline1)
end

function source.link_exists(State, filename)
  if State.link_cache == nil then
    State.link_cache = {}
  end
  if State.link_cache[filename] == nil then
    State.link_cache[filename] = file_exists(filename)
  end
  return State.link_cache[filename]
end

function Text.redraw_all(State)
--?   print('clearing fragments')
  State.line_cache = {}
  for i=1,#State.lines do
    State.line_cache[i] = {}
  end
  State.link_cache = {}
end

function Text.clear_screen_line_cache(State, line_index)
  State.line_cache[line_index].fragments = nil
  State.line_cache[line_index].screen_line_starting_pos = nil
end

function trim(s)
  return s:gsub('^%s+', ''):gsub('%s+$', '')
end

function ltrim(s)
  return s:gsub('^%s+', '')
end

function rtrim(s)
  return s:gsub('%s+$', '')
end

function starts_with(s, prefix)
  if #s < #prefix then
    return false
  end
  for i=1,#prefix do
    if s:sub(i,i) ~= prefix:sub(i,i) then
      return false
    end
  end
  return true
end

function ends_with(s, suffix)
  if #s < #suffix then
    return false
  end
  for i=0,#suffix-1 do
    if s:sub(#s-i,#s-i) ~= suffix:sub(#suffix-i,#suffix-i) then
      return false
    end
  end
  return true
end
