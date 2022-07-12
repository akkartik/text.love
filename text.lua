-- text editor, particularly text drawing, horizontal wrap, vertical scrolling
Text = {}

require 'search'
require 'select'
require 'undo'
require 'text_tests'

-- return values:
--  y coordinate drawn until in px
--  position of start of final screen line drawn
function Text.draw(State, line, line_index, top, left, right)
--?   print('text.draw', line_index)
  App.color(Text_color)
  -- wrap long lines
  local x = left
  local y = top
  local pos = 1
  local screen_line_starting_pos = 1
  if line.fragments == nil then
    Text.compute_fragments(line, left, right)
  end
  Text.populate_screen_line_starting_pos(line, left, right)
--?   print('--')
  for _, f in ipairs(line.fragments) do
    local frag, frag_text = f.data, f.text
    -- render fragment
    local frag_width = App.width(frag_text)
    local frag_len = utf8.len(frag)
--?     local s=tostring
--?     print('('..s(x)..','..s(y)..') '..frag..'('..s(frag_width)..' vs '..s(right)..') '..s(line_index)..' vs '..s(State.screen_top1.line)..'; '..s(pos)..' vs '..s(State.screen_top1.pos)..'; bottom: '..s(State.screen_bottom1.line)..'/'..s(State.screen_bottom1.pos))
    if x + frag_width > right then
      assert(x > left)  -- no overfull lines
      -- update y only after drawing the first screen line of screen top
      if Text.lt1(State.screen_top1, {line=line_index, pos=pos}) then
        y = y + State.line_height
        if y + State.line_height > App.screen.height then
--?           print('b', y, App.screen.height, '=>', screen_line_starting_pos)
          return y, screen_line_starting_pos
        end
        screen_line_starting_pos = pos
--?         print('text: new screen line', y, App.screen.height, screen_line_starting_pos)
      end
      x = left
    end
--?     print('checking to draw', pos, State.screen_top1.pos)
    -- don't draw text above screen top
    if Text.le1(State.screen_top1, {line=line_index, pos=pos}) then
      if State.selection1.line then
        local lo, hi = Text.clip_selection(line_index, pos, pos+frag_len, left, right)
        Text.draw_highlight(line, x,y, pos, lo,hi)
      end
--?       print('drawing '..frag)
      App.screen.draw(frag_text, x,y)
    end
    -- render cursor if necessary
    if line_index == State.cursor1.line then
      if pos <= State.cursor1.pos and pos + frag_len > State.cursor1.pos then
        if State.search_term then
          if State.lines[State.cursor1.line].data:sub(State.cursor1.pos, State.cursor1.pos+utf8.len(State.search_term)-1) == State.search_term then
            local lo_px = Text.draw_highlight(line, x,y, pos, State.cursor1.pos, State.cursor1.pos+utf8.len(State.search_term))
            App.color(Text_color)
            love.graphics.print(State.search_term, x+lo_px,y)
          end
        else
          Text.draw_cursor(State, x+Text.x(frag, State.cursor1.pos-pos+1), y)
        end
      end
    end
    x = x + frag_width
    pos = pos + frag_len
  end
  if State.search_term == nil then
    if line_index == State.cursor1.line and State.cursor1.pos == pos then
      Text.draw_cursor(State, x, y)
    end
  end
  return y, screen_line_starting_pos
end
-- manual tests:
--  draw with small screen width of 100

function Text.draw_cursor(State, x, y)
  -- blink every 0.5s
  if math.floor(Cursor_time*2)%2 == 0 then
    App.color(Cursor_color)
    love.graphics.rectangle('fill', x,y, 3,State.line_height)
    App.color(Text_color)
  end
  State.cursor_x = x
  State.cursor_y = y+State.line_height
end

function Text.compute_fragments(line, left, right)
--?   print('compute_fragments', right)
  line.fragments = {}
  local x = left
  -- try to wrap at word boundaries
  for frag in line.data:gmatch('%S*%s*') do
    local frag_text = App.newText(love.graphics.getFont(), frag)
    local frag_width = App.width(frag_text)
--?     print('x: '..tostring(x)..'; '..tostring(right-x)..'px to go')
--?     print('frag: ^'..frag..'$ is '..tostring(frag_width)..'px wide')
    if x + frag_width > right then
      while x + frag_width > right do
--?         print(x, frag, frag_width, right)
        if x < 0.8*right then
--?           print(frag, x, frag_width, right)
          -- long word; chop it at some letter
          -- We're not going to reimplement TeX here.
          local bpos = Text.nearest_pos_less_than(frag, right - x)
          assert(bpos > 0)  -- avoid infinite loop when window is too narrow
          local boffset = Text.offset(frag, bpos+1)  -- byte _after_ bpos
--?           print('space for '..tostring(bpos)..' graphemes, '..tostring(boffset)..' bytes')
          local frag1 = string.sub(frag, 1, boffset-1)
          local frag1_text = App.newText(love.graphics.getFont(), frag1)
          local frag1_width = App.width(frag1_text)
--?           print(frag, x, frag1_width, right)
          assert(x + frag1_width <= right)
--?           print('inserting '..frag1..' of width '..tostring(frag1_width)..'px')
          table.insert(line.fragments, {data=frag1, text=frag1_text})
          frag = string.sub(frag, boffset)
          frag_text = App.newText(love.graphics.getFont(), frag)
          frag_width = App.width(frag_text)
        end
        x = left  -- new line
      end
    end
    if #frag > 0 then
--?       print('inserting '..frag..' of width '..tostring(frag_width)..'px')
      table.insert(line.fragments, {data=frag, text=frag_text})
    end
    x = x + frag_width
  end
end

function Text.textinput(t)
  if App.mouse_down(1) then return end
  if App.ctrl_down() or App.alt_down() or App.cmd_down() then return end
  local before = snapshot(Editor_state.cursor1.line)
--?   print(Editor_state.screen_top1.line, Editor_state.screen_top1.pos, Editor_state.cursor1.line, Editor_state.cursor1.pos, Editor_state.screen_bottom1.line, Editor_state.screen_bottom1.pos)
  Text.insert_at_cursor(t)
  if Editor_state.cursor_y >= App.screen.height - Editor_state.line_height then
    Text.populate_screen_line_starting_pos(Editor_state.lines[Editor_state.cursor1.line], Editor_state.margin_left, App.screen.width-Editor_state.margin_right)
    Text.snap_cursor_to_bottom_of_screen(Editor_state.margin_left, App.screen.width-Editor_state.margin_right)
--?     print('=>', Editor_state.screen_top1.line, Editor_state.screen_top1.pos, Editor_state.cursor1.line, Editor_state.cursor1.pos, Editor_state.screen_bottom1.line, Editor_state.screen_bottom1.pos)
  end
  record_undo_event({before=before, after=snapshot(Editor_state.cursor1.line)})
end

function Text.insert_at_cursor(t)
  local byte_offset = Text.offset(Editor_state.lines[Editor_state.cursor1.line].data, Editor_state.cursor1.pos)
  Editor_state.lines[Editor_state.cursor1.line].data = string.sub(Editor_state.lines[Editor_state.cursor1.line].data, 1, byte_offset-1)..t..string.sub(Editor_state.lines[Editor_state.cursor1.line].data, byte_offset)
  Text.clear_cache(Editor_state.lines[Editor_state.cursor1.line])
  Editor_state.cursor1.pos = Editor_state.cursor1.pos+1
end

-- Don't handle any keys here that would trigger love.textinput above.
function Text.keychord_pressed(State, chord)
--?   print('chord', chord, State.selection1.line, State.selection1.pos)
  --== shortcuts that mutate text
  if chord == 'return' then
    local before_line = State.cursor1.line
    local before = snapshot(before_line)
    Text.insert_return()
    State.selection1 = {}
    if (State.cursor_y + State.line_height) > App.screen.height then
      Text.snap_cursor_to_bottom_of_screen(State.margin_left, App.screen.width-State.margin_right)
    end
    schedule_save()
    record_undo_event({before=before, after=snapshot(before_line, State.cursor1.line)})
  elseif chord == 'tab' then
    local before = snapshot(State.cursor1.line)
--?     print(State.screen_top1.line, State.screen_top1.pos, State.cursor1.line, State.cursor1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
    Text.insert_at_cursor('\t')
    if State.cursor_y >= App.screen.height - State.line_height then
      Text.populate_screen_line_starting_pos(State.lines[State.cursor1.line], State.margin_left, App.screen.width-State.margin_right)
      Text.snap_cursor_to_bottom_of_screen(State.margin_left, App.screen.width-State.margin_right)
--?       print('=>', State.screen_top1.line, State.screen_top1.pos, State.cursor1.line, State.cursor1.pos, State.screen_bottom1.line, State.screen_bottom1.pos)
    end
    schedule_save()
    record_undo_event({before=before, after=snapshot(State.cursor1.line)})
  elseif chord == 'backspace' then
    if State.selection1.line then
      Text.delete_selection(State.margin_left, App.screen.width-State.margin_right)
      schedule_save()
      return
    end
    local before
    if State.cursor1.pos > 1 then
      before = snapshot(State.cursor1.line)
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
      before = snapshot(State.cursor1.line-1, State.cursor1.line)
      if State.lines[State.cursor1.line-1].mode == 'drawing' then
        table.remove(State.lines, State.cursor1.line-1)
      else
        -- join lines
        State.cursor1.pos = utf8.len(State.lines[State.cursor1.line-1].data)+1
        State.lines[State.cursor1.line-1].data = State.lines[State.cursor1.line-1].data..State.lines[State.cursor1.line].data
        table.remove(State.lines, State.cursor1.line)
      end
      State.cursor1.line = State.cursor1.line-1
    end
    if Text.lt1(State.cursor1, State.screen_top1) then
      local top2 = Text.to2(State.screen_top1, State.margin_left, App.screen.width-State.margin_right)
      top2 = Text.previous_screen_line(top2, State.margin_left, App.screen.width-State.margin_right)
      State.screen_top1 = Text.to1(top2)
      Text.redraw_all()  -- if we're scrolling, reclaim all fragments to avoid memory leaks
    end
    Text.clear_cache(State.lines[State.cursor1.line])
    assert(Text.le1(State.screen_top1, State.cursor1))
    schedule_save()
    record_undo_event({before=before, after=snapshot(State.cursor1.line)})
  elseif chord == 'delete' then
    if State.selection1.line then
      Text.delete_selection(State.margin_left, App.screen.width-State.margin_right)
      schedule_save()
      return
    end
    local before
    if State.cursor1.pos <= utf8.len(State.lines[State.cursor1.line].data) then
      before = snapshot(State.cursor1.line)
    else
      before = snapshot(State.cursor1.line, State.cursor1.line+1)
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
      if State.lines[State.cursor1.line+1].mode == 'drawing' then
        table.remove(State.lines, State.cursor1.line+1)
      else
        -- join lines
        State.lines[State.cursor1.line].data = State.lines[State.cursor1.line].data..State.lines[State.cursor1.line+1].data
        table.remove(State.lines, State.cursor1.line+1)
      end
    end
    Text.clear_cache(State.lines[State.cursor1.line])
    schedule_save()
    record_undo_event({before=before, after=snapshot(State.cursor1.line)})
  --== shortcuts that move the cursor
  elseif chord == 'left' then
    Text.left(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'right' then
    Text.right(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'S-left' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.left(State.margin_left, App.screen.width-State.margin_right)
  elseif chord == 'S-right' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.right(State.margin_left, App.screen.width-State.margin_right)
  -- C- hotkeys reserved for drawings, so we'll use M-
  elseif chord == 'M-left' then
    Text.word_left(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'M-right' then
    Text.word_right(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'M-S-left' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.word_left(State.margin_left, App.screen.width-State.margin_right)
  elseif chord == 'M-S-right' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.word_right(State.margin_left, App.screen.width-State.margin_right)
  elseif chord == 'home' then
    Text.start_of_line()
    State.selection1 = {}
  elseif chord == 'end' then
    Text.end_of_line(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'S-home' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.start_of_line()
  elseif chord == 'S-end' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.end_of_line(State.margin_left, App.screen.width-State.margin_right)
  elseif chord == 'up' then
    Text.up(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'down' then
    Text.down(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'S-up' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.up(State.margin_left, App.screen.width-State.margin_right)
  elseif chord == 'S-down' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.down(State.margin_left, App.screen.width-State.margin_right)
  elseif chord == 'pageup' then
    Text.pageup(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'pagedown' then
    Text.pagedown(State.margin_left, App.screen.width-State.margin_right)
    State.selection1 = {}
  elseif chord == 'S-pageup' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.pageup(State.margin_left, App.screen.width-State.margin_right)
  elseif chord == 'S-pagedown' then
    if State.selection1.line == nil then
      State.selection1 = {line=State.cursor1.line, pos=State.cursor1.pos}
    end
    Text.pagedown(State.margin_left, App.screen.width-State.margin_right)
  end
end

function Text.insert_return()
  local byte_offset = Text.offset(Editor_state.lines[Editor_state.cursor1.line].data, Editor_state.cursor1.pos)
  table.insert(Editor_state.lines, Editor_state.cursor1.line+1, {mode='text', data=string.sub(Editor_state.lines[Editor_state.cursor1.line].data, byte_offset)})
  Editor_state.lines[Editor_state.cursor1.line].data = string.sub(Editor_state.lines[Editor_state.cursor1.line].data, 1, byte_offset-1)
  Text.clear_cache(Editor_state.lines[Editor_state.cursor1.line])
  Text.clear_cache(Editor_state.lines[Editor_state.cursor1.line+1])
  Editor_state.cursor1.line = Editor_state.cursor1.line+1
  Editor_state.cursor1.pos = 1
end

function Text.pageup(left, right)
--?   print('pageup')
  -- duplicate some logic from love.draw
  local top2 = Text.to2(Editor_state.screen_top1, left, right)
--?   print(App.screen.height)
  local y = App.screen.height - Editor_state.line_height
  while y >= Editor_state.margin_top do
--?     print(y, top2.line, top2.screen_line, top2.screen_pos)
    if Editor_state.screen_top1.line == 1 and Editor_state.screen_top1.pos == 1 then break end
    if Editor_state.lines[Editor_state.screen_top1.line].mode == 'text' then
      y = y - Editor_state.line_height
    elseif Editor_state.lines[Editor_state.screen_top1.line].mode == 'drawing' then
      y = y - Editor_state.drawing_padding_height - Drawing.pixels(Editor_state.lines[Editor_state.screen_top1.line].h)
    end
    top2 = Text.previous_screen_line(top2, left, right)
  end
  Editor_state.screen_top1 = Text.to1(top2)
  Editor_state.cursor1.line = Editor_state.screen_top1.line
  Editor_state.cursor1.pos = Editor_state.screen_top1.pos
  Text.move_cursor_down_to_next_text_line_while_scrolling_again_if_necessary(left, right)
--?   print(Editor_state.cursor1.line, Editor_state.cursor1.pos, Editor_state.screen_top1.line, Editor_state.screen_top1.pos)
--?   print('pageup end')
end

function Text.pagedown(left, right)
--?   print('pagedown')
  -- If a line/paragraph gets to a page boundary, I often want to scroll
  -- before I get to the bottom.
  -- However, only do this if it makes forward progress.
  local top2 = Text.to2(Editor_state.screen_bottom1, left, right)
  if top2.screen_line > 1 then
    top2.screen_line = math.max(top2.screen_line-10, 1)
  end
  local new_top1 = Text.to1(top2)
  if Text.lt1(Editor_state.screen_top1, new_top1) then
    Editor_state.screen_top1 = new_top1
  else
    Editor_state.screen_top1.line = Editor_state.screen_bottom1.line
    Editor_state.screen_top1.pos = Editor_state.screen_bottom1.pos
  end
--?   print('setting top to', Editor_state.screen_top1.line, Editor_state.screen_top1.pos)
  Editor_state.cursor1.line = Editor_state.screen_top1.line
  Editor_state.cursor1.pos = Editor_state.screen_top1.pos
  Text.move_cursor_down_to_next_text_line_while_scrolling_again_if_necessary(left, right)
--?   print('top now', Editor_state.screen_top1.line)
  Text.redraw_all()  -- if we're scrolling, reclaim all fragments to avoid memory leaks
--?   print('pagedown end')
end

function Text.up(left, right)
  assert(Editor_state.lines[Editor_state.cursor1.line].mode == 'text')
--?   print('up', Editor_state.cursor1.line, Editor_state.cursor1.pos, Editor_state.screen_top1.line, Editor_state.screen_top1.pos)
  local screen_line_index,screen_line_starting_pos = Text.pos_at_start_of_cursor_screen_line(left, right)
  if screen_line_starting_pos == 1 then
--?     print('cursor is at first screen line of its line')
    -- line is done; skip to previous text line
    local new_cursor_line = Editor_state.cursor1.line
    while new_cursor_line > 1 do
      new_cursor_line = new_cursor_line-1
      if Editor_state.lines[new_cursor_line].mode == 'text' then
--?         print('found previous text line')
        Editor_state.cursor1.line = new_cursor_line
        Text.populate_screen_line_starting_pos(Editor_state.lines[Editor_state.cursor1.line], left, right)
        -- previous text line found, pick its final screen line
--?         print('has multiple screen lines')
        local screen_line_starting_pos = Editor_state.lines[Editor_state.cursor1.line].screen_line_starting_pos
--?         print(#screen_line_starting_pos)
        screen_line_starting_pos = screen_line_starting_pos[#screen_line_starting_pos]
--?         print('previous screen line starts at pos '..tostring(screen_line_starting_pos)..' of its line')
        if Editor_state.screen_top1.line > Editor_state.cursor1.line then
          Editor_state.screen_top1.line = Editor_state.cursor1.line
          Editor_state.screen_top1.pos = screen_line_starting_pos
--?           print('pos of top of screen is also '..tostring(Editor_state.screen_top1.pos)..' of the same line')
        end
        local screen_line_starting_byte_offset = Text.offset(Editor_state.lines[Editor_state.cursor1.line].data, screen_line_starting_pos)
        local s = string.sub(Editor_state.lines[Editor_state.cursor1.line].data, screen_line_starting_byte_offset)
        Editor_state.cursor1.pos = screen_line_starting_pos + Text.nearest_cursor_pos(s, Editor_state.cursor_x, left) - 1
        break
      end
    end
    if Editor_state.cursor1.line < Editor_state.screen_top1.line then
      Editor_state.screen_top1.line = Editor_state.cursor1.line
    end
  else
    -- move up one screen line in current line
--?     print('cursor is NOT at first screen line of its line')
    assert(screen_line_index > 1)
    new_screen_line_starting_pos = Editor_state.lines[Editor_state.cursor1.line].screen_line_starting_pos[screen_line_index-1]
--?     print('switching pos of screen line at cursor from '..tostring(screen_line_starting_pos)..' to '..tostring(new_screen_line_starting_pos))
    if Editor_state.screen_top1.line == Editor_state.cursor1.line and Editor_state.screen_top1.pos == screen_line_starting_pos then
      Editor_state.screen_top1.pos = new_screen_line_starting_pos
--?       print('also setting pos of top of screen to '..tostring(Editor_state.screen_top1.pos))
    end
    local new_screen_line_starting_byte_offset = Text.offset(Editor_state.lines[Editor_state.cursor1.line].data, new_screen_line_starting_pos)
    local s = string.sub(Editor_state.lines[Editor_state.cursor1.line].data, new_screen_line_starting_byte_offset)
    Editor_state.cursor1.pos = new_screen_line_starting_pos + Text.nearest_cursor_pos(s, Editor_state.cursor_x, left) - 1
--?     print('cursor pos is now '..tostring(Editor_state.cursor1.pos))
  end
end

function Text.down(left, right)
  assert(Editor_state.lines[Editor_state.cursor1.line].mode == 'text')
--?   print('down', Editor_state.cursor1.line, Editor_state.cursor1.pos, Editor_state.screen_top1.line, Editor_state.screen_top1.pos, Editor_state.screen_bottom1.line, Editor_state.screen_bottom1.pos)
  if Text.cursor_at_final_screen_line(left, right) then
    -- line is done, skip to next text line
--?     print('cursor at final screen line of its line')
    local new_cursor_line = Editor_state.cursor1.line
    while new_cursor_line < #Editor_state.lines do
      new_cursor_line = new_cursor_line+1
      if Editor_state.lines[new_cursor_line].mode == 'text' then
        Editor_state.cursor1.line = new_cursor_line
        Editor_state.cursor1.pos = Text.nearest_cursor_pos(Editor_state.lines[Editor_state.cursor1.line].data, Editor_state.cursor_x, left)
--?         print(Editor_state.cursor1.pos)
        break
      end
    end
    if Editor_state.cursor1.line > Editor_state.screen_bottom1.line then
--?       print('screen top before:', Editor_state.screen_top1.line, Editor_state.screen_top1.pos)
--?       print('scroll up preserving cursor')
      Text.snap_cursor_to_bottom_of_screen(left, right)
--?       print('screen top after:', Editor_state.screen_top1.line, Editor_state.screen_top1.pos)
    end
  else
    -- move down one screen line in current line
    local scroll_down = false
    if Text.le1(Editor_state.screen_bottom1, Editor_state.cursor1) then
      scroll_down = true
    end
--?     print('cursor is NOT at final screen line of its line')
    local screen_line_index, screen_line_starting_pos = Text.pos_at_start_of_cursor_screen_line(left, right)
    new_screen_line_starting_pos = Editor_state.lines[Editor_state.cursor1.line].screen_line_starting_pos[screen_line_index+1]
--?     print('switching pos of screen line at cursor from '..tostring(screen_line_starting_pos)..' to '..tostring(new_screen_line_starting_pos))
    local new_screen_line_starting_byte_offset = Text.offset(Editor_state.lines[Editor_state.cursor1.line].data, new_screen_line_starting_pos)
    local s = string.sub(Editor_state.lines[Editor_state.cursor1.line].data, new_screen_line_starting_byte_offset)
    Editor_state.cursor1.pos = new_screen_line_starting_pos + Text.nearest_cursor_pos(s, Editor_state.cursor_x, left) - 1
--?     print('cursor pos is now', Editor_state.cursor1.line, Editor_state.cursor1.pos)
    if scroll_down then
--?       print('scroll up preserving cursor')
      Text.snap_cursor_to_bottom_of_screen(left, right)
--?       print('screen top after:', Editor_state.screen_top1.line, Editor_state.screen_top1.pos)
    end
  end
--?   print('=>', Editor_state.cursor1.line, Editor_state.cursor1.pos, Editor_state.screen_top1.line, Editor_state.screen_top1.pos, Editor_state.screen_bottom1.line, Editor_state.screen_bottom1.pos)
end

function Text.start_of_line()
  Editor_state.cursor1.pos = 1
  if Text.lt1(Editor_state.cursor1, Editor_state.screen_top1) then
    Editor_state.screen_top1 = {line=Editor_state.cursor1.line, pos=Editor_state.cursor1.pos}  -- copy
  end
end

function Text.end_of_line(left, right)
  Editor_state.cursor1.pos = utf8.len(Editor_state.lines[Editor_state.cursor1.line].data) + 1
  local _,botpos = Text.pos_at_start_of_cursor_screen_line(left, right)
  local botline1 = {line=Editor_state.cursor1.line, pos=botpos}
  if Text.cursor_past_screen_bottom() then
    Text.snap_cursor_to_bottom_of_screen(left, right)
  end
end

function Text.word_left(left, right)
  -- skip some whitespace
  while true do
    if Editor_state.cursor1.pos == 1 then
      break
    end
    if Text.match(Editor_state.lines[Editor_state.cursor1.line].data, Editor_state.cursor1.pos-1, '%S') then
      break
    end
    Text.left(left, right)
  end
  -- skip some non-whitespace
  while true do
    Text.left(left, right)
    if Editor_state.cursor1.pos == 1 then
      break
    end
    assert(Editor_state.cursor1.pos > 1)
    if Text.match(Editor_state.lines[Editor_state.cursor1.line].data, Editor_state.cursor1.pos-1, '%s') then
      break
    end
  end
end

function Text.word_right(left, right)
  -- skip some whitespace
  while true do
    if Editor_state.cursor1.pos > utf8.len(Editor_state.lines[Editor_state.cursor1.line].data) then
      break
    end
    if Text.match(Editor_state.lines[Editor_state.cursor1.line].data, Editor_state.cursor1.pos, '%S') then
      break
    end
    Text.right_without_scroll()
  end
  while true do
    Text.right_without_scroll()
    if Editor_state.cursor1.pos > utf8.len(Editor_state.lines[Editor_state.cursor1.line].data) then
      break
    end
    if Text.match(Editor_state.lines[Editor_state.cursor1.line].data, Editor_state.cursor1.pos, '%s') then
      break
    end
  end
  if Text.cursor_past_screen_bottom() then
    Text.snap_cursor_to_bottom_of_screen(left, right)
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

function Text.left(left, right)
  assert(Editor_state.lines[Editor_state.cursor1.line].mode == 'text')
  if Editor_state.cursor1.pos > 1 then
    Editor_state.cursor1.pos = Editor_state.cursor1.pos-1
  else
    local new_cursor_line = Editor_state.cursor1.line
    while new_cursor_line > 1 do
      new_cursor_line = new_cursor_line-1
      if Editor_state.lines[new_cursor_line].mode == 'text' then
        Editor_state.cursor1.line = new_cursor_line
        Editor_state.cursor1.pos = utf8.len(Editor_state.lines[Editor_state.cursor1.line].data) + 1
        break
      end
    end
  end
  if Text.lt1(Editor_state.cursor1, Editor_state.screen_top1) then
    local top2 = Text.to2(Editor_state.screen_top1, left, right)
    top2 = Text.previous_screen_line(top2, left, right)
    Editor_state.screen_top1 = Text.to1(top2)
  end
end

function Text.right(left, right)
  Text.right_without_scroll()
  if Text.cursor_past_screen_bottom() then
    Text.snap_cursor_to_bottom_of_screen(left, right)
  end
end

function Text.right_without_scroll()
  assert(Editor_state.lines[Editor_state.cursor1.line].mode == 'text')
  if Editor_state.cursor1.pos <= utf8.len(Editor_state.lines[Editor_state.cursor1.line].data) then
    Editor_state.cursor1.pos = Editor_state.cursor1.pos+1
  else
    local new_cursor_line = Editor_state.cursor1.line
    while new_cursor_line <= #Editor_state.lines-1 do
      new_cursor_line = new_cursor_line+1
      if Editor_state.lines[new_cursor_line].mode == 'text' then
        Editor_state.cursor1.line = new_cursor_line
        Editor_state.cursor1.pos = 1
        break
      end
    end
  end
end

function Text.pos_at_start_of_cursor_screen_line(left, right)
  Text.populate_screen_line_starting_pos(Editor_state.lines[Editor_state.cursor1.line], left, right)
  for i=#Editor_state.lines[Editor_state.cursor1.line].screen_line_starting_pos,1,-1 do
    local spos = Editor_state.lines[Editor_state.cursor1.line].screen_line_starting_pos[i]
    if spos <= Editor_state.cursor1.pos then
      return i,spos
    end
  end
  assert(false)
end

function Text.cursor_at_final_screen_line(left, right)
  Text.populate_screen_line_starting_pos(Editor_state.lines[Editor_state.cursor1.line], left, right)
  local screen_lines = Editor_state.lines[Editor_state.cursor1.line].screen_line_starting_pos
--?   print(screen_lines[#screen_lines], Editor_state.cursor1.pos)
  return screen_lines[#screen_lines] <= Editor_state.cursor1.pos
end

function Text.move_cursor_down_to_next_text_line_while_scrolling_again_if_necessary(left, right)
  local y = Editor_state.margin_top
  while Editor_state.cursor1.line <= #Editor_state.lines do
    if Editor_state.lines[Editor_state.cursor1.line].mode == 'text' then
      break
    end
--?     print('cursor skips', Editor_state.cursor1.line)
    y = y + Editor_state.drawing_padding_height + Drawing.pixels(Editor_state.lines[Editor_state.cursor1.line].h)
    Editor_state.cursor1.line = Editor_state.cursor1.line + 1
  end
  -- hack: insert a text line at bottom of file if necessary
  if Editor_state.cursor1.line > #Editor_state.lines then
    assert(Editor_state.cursor1.line == #Editor_state.lines+1)
    table.insert(Editor_state.lines, {mode='text', data=''})
  end
--?   print(y, App.screen.height, App.screen.height-Editor_state.line_height)
  if y > App.screen.height - Editor_state.line_height then
--?     print('scroll up')
    Text.snap_cursor_to_bottom_of_screen(left, right)
  end
end

-- should never modify Editor_state.cursor1
function Text.snap_cursor_to_bottom_of_screen(left, right)
  local top2 = Text.to2(Editor_state.cursor1, left, right)
  top2.screen_pos = 1  -- start of screen line
--?   print('cursor pos '..tostring(Editor_state.cursor1.pos)..' is on the #'..tostring(top2.screen_line)..' screen line down')
  local y = App.screen.height - Editor_state.line_height
  -- duplicate some logic from love.draw
  while true do
--?     print(y, 'top2:', top2.line, top2.screen_line, top2.screen_pos)
    if top2.line == 1 and top2.screen_line == 1 then break end
    if top2.screen_line > 1 or Editor_state.lines[top2.line-1].mode == 'text' then
      local h = Editor_state.line_height
      if y - h < Editor_state.margin_top then
        break
      end
      y = y - h
    else
      assert(top2.line > 1)
      assert(Editor_state.lines[top2.line-1].mode == 'drawing')
      -- We currently can't draw partial drawings, so either skip it entirely
      -- or not at all.
      local h = Editor_state.drawing_padding_height + Drawing.pixels(Editor_state.lines[top2.line-1].h)
      if y - h < Editor_state.margin_top then
        break
      end
--?       print('skipping drawing of height', h)
      y = y - h
    end
    top2 = Text.previous_screen_line(top2, left, right)
  end
--?   print('top2 finally:', top2.line, top2.screen_line, top2.screen_pos)
  Editor_state.screen_top1 = Text.to1(top2)
--?   print('top1 finally:', Editor_state.screen_top1.line, Editor_state.screen_top1.pos)
  Text.redraw_all()  -- if we're scrolling, reclaim all fragments to avoid memory leaks
end

function Text.in_line(line, x,y, left,right)
  if line.starty == nil then return false end  -- outside current page
  if x < left then return false end
  if y < line.starty then return false end
  Text.populate_screen_line_starting_pos(line, left, right)
  return y < line.starty + Editor_state.line_height*(#line.screen_line_starting_pos - Text.screen_line_index(line, line.startpos) + 1)
end

-- convert mx,my in pixels to schema-1 coordinates
function Text.to_pos_on_line(line, mx, my, left, right)
  if line.fragments == nil then
    Text.compute_fragments(line, left, right)
  end
  assert(my >= line.starty)
  -- duplicate some logic from Text.draw
  local y = line.starty
  local start_screen_line_index = Text.screen_line_index(line, line.startpos)
  for screen_line_index = start_screen_line_index,#line.screen_line_starting_pos do
    local screen_line_starting_pos = line.screen_line_starting_pos[screen_line_index]
    local screen_line_starting_byte_offset = Text.offset(line.data, screen_line_starting_pos)
--?     print('iter', y, screen_line_index, screen_line_starting_pos, string.sub(line.data, screen_line_starting_byte_offset))
    local nexty = y + Editor_state.line_height
    if my < nexty then
      -- On all wrapped screen lines but the final one, clicks past end of
      -- line position cursor on final character of screen line.
      -- (The final screen line positions past end of screen line as always.)
      if screen_line_index < #line.screen_line_starting_pos and mx > Text.screen_line_width(line, screen_line_index) then
--?         print('past end of non-final line; return')
        return line.screen_line_starting_pos[screen_line_index+1]-1
      end
      local s = string.sub(line.data, screen_line_starting_byte_offset)
--?       print('return', mx, Text.nearest_cursor_pos(s, mx, left), '=>', screen_line_starting_pos + Text.nearest_cursor_pos(s, mx, left) - 1)
      return screen_line_starting_pos + Text.nearest_cursor_pos(s, mx, left) - 1
    end
    y = nexty
  end
  assert(false)
end
-- manual test:
--  line: abc
--        def
--        gh
--  fragments: abc, def, gh
--  click inside e
--  line_starting_pos = 1 + 3 = 4
--  nearest_cursor_pos('defgh', mx) = 2
--  Editor_state.cursor1.pos = 4 + 2 - 1 = 5
-- manual test:
--  click inside h
--  line_starting_pos = 1 + 3 + 3 = 7
--  nearest_cursor_pos('gh', mx) = 2
--  Editor_state.cursor1.pos = 7 + 2 - 1 = 8

function Text.screen_line_width(line, i)
  local start_pos = line.screen_line_starting_pos[i]
  local start_offset = Text.offset(line.data, start_pos)
  local screen_line
  if i < #line.screen_line_starting_pos then
    local past_end_pos = line.screen_line_starting_pos[i+1]
    local past_end_offset = Text.offset(line.data, past_end_pos)
    screen_line = string.sub(line.data, start_offset, past_end_offset-1)
  else
    screen_line = string.sub(line.data, start_pos)
  end
  local screen_line_text = App.newText(love.graphics.getFont(), screen_line)
  return App.width(screen_line_text)
end

function Text.screen_line_index(line, pos)
  for i = #line.screen_line_starting_pos,1,-1 do
    if line.screen_line_starting_pos[i] <= pos then
      return i
    end
  end
end

-- convert x pixel coordinate to pos
-- oblivious to wrapping
function Text.nearest_cursor_pos(line, x, left)
  if x == 0 then
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

function Text.nearest_pos_less_than(line, x)  -- x DOES NOT include left margin
  if x == 0 then
    return 1
  end
  local len = utf8.len(line)
  local max_x = Text.x(line, len+1)
  if x > max_x then
    return len+1
  end
  local left, right = 1, len+1
--?   print('--')
  while true do
    local curr = math.floor((left+right)/2)
    local currxmin = Text.x(line, curr+1)
    local currxmax = Text.x(line, curr+2)
--?     print(x, left, right, curr, currxmin, currxmax)
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

function Text.x(s, pos)
  local offset = Text.offset(s, pos)
  local s_before = s:sub(1, offset-1)
  local text_before = App.newText(love.graphics.getFont(), s_before)
  return App.width(text_before)
end

function Text.to2(pos1, left, right)
  if Editor_state.lines[pos1.line].mode == 'drawing' then
    return {line=pos1.line, screen_line=1, screen_pos=1}
  end
  local result = {line=pos1.line, screen_line=1}
  Text.populate_screen_line_starting_pos(Editor_state.lines[pos1.line], left, right)
  for i=#Editor_state.lines[pos1.line].screen_line_starting_pos,1,-1 do
    local spos = Editor_state.lines[pos1.line].screen_line_starting_pos[i]
    if spos <= pos1.pos then
      result.screen_line = i
      result.screen_pos = pos1.pos - spos + 1
      break
    end
  end
  assert(result.screen_pos)
  return result
end

function Text.to1(pos2)
  local result = {line=pos2.line, pos=pos2.screen_pos}
  if pos2.screen_line > 1 then
    result.pos = Editor_state.lines[pos2.line].screen_line_starting_pos[pos2.screen_line] + pos2.screen_pos - 1
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
    print(Editor_state.cursor1.line, Editor_state.cursor1.pos, #Editor_state.lines[Editor_state.cursor1.line].data, Editor_state.lines[Editor_state.cursor1.line].data)
    print(pos1, #s, s)
  end
  assert(result)
  return result
end

function Text.previous_screen_line(pos2, left, right)
  if pos2.screen_line > 1 then
    return {line=pos2.line, screen_line=pos2.screen_line-1, screen_pos=1}
  elseif pos2.line == 1 then
    return pos2
  elseif Editor_state.lines[pos2.line-1].mode == 'drawing' then
    return {line=pos2.line-1, screen_line=1, screen_pos=1}
  else
    local l = Editor_state.lines[pos2.line-1]
    Text.populate_screen_line_starting_pos(Editor_state.lines[pos2.line-1], left, right)
    return {line=pos2.line-1, screen_line=#Editor_state.lines[pos2.line-1].screen_line_starting_pos, screen_pos=1}
  end
end

function Text.populate_screen_line_starting_pos(line, left, right)
  if line.screen_line_starting_pos then
    return
  end
  -- duplicate some logic from Text.draw
  if line.fragments == nil then
    Text.compute_fragments(line, left, right)
  end
  line.screen_line_starting_pos = {1}
  local x = left
  local pos = 1
  for _, f in ipairs(line.fragments) do
    local frag, frag_text = f.data, f.text
    -- render fragment
    local frag_width = App.width(frag_text)
    if x + frag_width > right then
      x = left
      table.insert(line.screen_line_starting_pos, pos)
    end
    x = x + frag_width
    local frag_len = utf8.len(frag)
    pos = pos + frag_len
  end
end

function Text.tweak_screen_top_and_cursor(left, right)
--?   print('a', Editor_state.selection1.line)
  if Editor_state.screen_top1.pos == 1 then return end
  local line = Editor_state.lines[Editor_state.screen_top1.line]
  Text.populate_screen_line_starting_pos(line, left, right)
  for i=2,#line.screen_line_starting_pos do
    local pos = line.screen_line_starting_pos[i]
    if pos == Editor_state.screen_top1.pos then
      break
    end
    if pos > Editor_state.screen_top1.pos then
      -- make sure screen top is at start of a screen line
      local prev = line.screen_line_starting_pos[i-1]
      if Editor_state.screen_top1.pos - prev < pos - Editor_state.screen_top1.pos then
        Editor_state.screen_top1.pos = prev
      else
        Editor_state.screen_top1.pos = pos
      end
      break
    end
  end
  -- make sure cursor is on screen
  if Text.lt1(Editor_state.cursor1, Editor_state.screen_top1) then
    Editor_state.cursor1 = {line=Editor_state.screen_top1.line, pos=Editor_state.screen_top1.pos}
  elseif Editor_state.cursor1.line >= Editor_state.screen_bottom1.line then
--?     print('too low')
    if Text.cursor_past_screen_bottom() then
--?       print('tweak')
      local line = Editor_state.lines[Editor_state.screen_bottom1.line]
      Editor_state.cursor1 = {
          line=Editor_state.screen_bottom1.line,
          pos=Text.to_pos_on_line(line, App.screen.width-5, App.screen.height-5, left, right),
      }
    end
  end
end

-- slightly expensive since it redraws the screen
function Text.cursor_past_screen_bottom()
  App.draw()
  return Editor_state.cursor_y >= App.screen.height - Editor_state.line_height
  -- this approach is cheaper and almost works, except on the final screen
  -- where file ends above bottom of screen
--?   local _,botpos = Text.pos_at_start_of_cursor_screen_line(left, right)
--?   local botline1 = {line=Editor_state.cursor1.line, pos=botpos}
--?   return Text.lt1(Editor_state.screen_bottom1, botline1)
end

function Text.redraw_all()
--?   print('clearing fragments')
  for _,line in ipairs(Editor_state.lines) do
    line.starty = nil
    line.startpos = nil
    Text.clear_cache(line)
  end
end

function Text.clear_cache(line)
  line.fragments = nil
  line.screen_line_starting_pos = nil
end
