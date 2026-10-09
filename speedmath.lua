math.randomseed(os.time())
for _ = 1, 3 do math.random() end

local function clear()
  if package.config:sub(1,1) == "\\" then os.execute("cls")
  else os.execute("clear") end
end

local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

local function ask(prompt, default)
  if default ~= nil then io.write(string.format("%s [%s]: ", prompt, tostring(default)))
  else io.write(prompt .. ": ") end
  local line = io.read("*l")
  if line == nil then return "" end
  line = trim(line)
  if line == "" and default ~= nil then return tostring(default) end
  return line
end

local function ask_number(prompt, default, min, max)
  while true do
    local s = ask(prompt, default)
    if s:lower() == "q" then return nil end
    local n = tonumber(s)
    if n then
      n = math.floor(n)
      if min and n < min then print("Too small.")
      elseif max and n > max then print("Too big.")
      else return n end
    else
      print("Enter a number (q to cancel).")
    end
  end
end

local function fmt2(n)
  if n < 0 then return "(" .. tostring(n) .. ")" end
  return tostring(n)
end

local function signed_mag(lo, hi)
  local m = math.random(lo, hi)
  if math.random(2) == 1 then m = -m end
  return m
end

local function gen_add(neg)
  local a, b = math.random(1, 9), math.random(1, 9)
  if neg then a, b = math.random(-9, 9), math.random(-9, 9) end
  return { text = string.format("%d + %s", a, fmt2(b)), answer = a + b }
end

local function gen_sub(neg)
  local a, b
  if neg then a, b = math.random(-20, 20), math.random(-20, 20)
  else a = math.random(2, 20); b = math.random(1, a) end
  return { text = string.format("%d - %s", a, fmt2(b)), answer = a - b }
end

local function gen_mul(neg)
  local a, b = math.random(2, 9), math.random(2, 9)
  if neg then a, b = signed_mag(2, 9), signed_mag(2, 9) end
  local sa = a < 0 and ("(" .. a .. ")") or tostring(a)
  return { text = string.format("%s * %s", sa, fmt2(b)), answer = a * b }
end

local function gen_div(neg)
  local b, ans = math.random(2, 10), math.random(2, 10)
  if neg then b, ans = signed_mag(2, 10), signed_mag(2, 10) end
  return { text = string.format("%d : %s", b * ans, fmt2(b)), answer = ans }
end

local GEN = { ["+"] = gen_add, ["-"] = gen_sub, ["*"] = gen_mul, [":"] = gen_div, ["/"] = gen_div }

local function gen_problem(ops, neg)
  local op
  if #ops == 1 and ops[1] == "mixed" then
    op = ({"+", "-", "*", ":"})[math.random(4)]
  elseif #ops == 1 then op = ops[1]
  else op = ops[math.random(#ops)] end
  return GEN[op](neg)
end

local function generate_dataset(ops, count, with_answers, neg)
  local lines = {}
  for i = 1, count do
    local p = gen_problem(ops, neg)
    lines[i] = with_answers and string.format("%d. %s=%d", i, p.text, p.answer)
                              or string.format("%d. %s", i, p.text)
  end
  return lines
end

local function parse_expr(expr)
  local as, op, bs = expr:match("^%s*%(?%s*(-?%d+)%s*%)?%s*([%+%-%*%:%/])%s*%(?%s*(-?%d+)%s*%)?%s*$")
  if not as then return nil end
  local a, b = tonumber(as), tonumber(bs)
  if op == "+" then return { text = trim(expr), answer = a + b }
  elseif op == "-" then return { text = trim(expr), answer = a - b }
  elseif op == "*" then return { text = trim(expr), answer = a * b }
  elseif op == ":" or op == "/" then
    if b == 0 then return nil end
    return { text = trim(expr), answer = a / b }
  end
  return nil
end

local function load_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local out = {}
  for raw in f:lines() do
    local line = trim(raw)
    if line ~= "" then
      local body = line:match("^%s*%d+%.%s*(.+)%s*$") or line
      local expr = body:match("^(.-)%s*=%s*-?%d*%.?%d*%s*$") or body
      if expr:find("[%+%-%*%:%/]") then
        local p = parse_expr(expr)
        if p then out[#out + 1] = p end
      end
    end
  end
  f:close()
  return out
end

local function shuffle_in_place(t)
  for i = #t, 2, -1 do
    local j = math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
end

local function stdin_is_tty()
  if package.config:sub(1,1) == "\\" then return false end
  local ok = os.execute("[ -t 0 ] 2>/dev/null")
  return ok == true or ok == 0
end

local function term_raw()
  os.execute("stty raw -echo 2>/dev/null")
end

local function term_cooked()
  if package.config:sub(1,1) ~= "\\" then
    os.execute("stty sane 2>/dev/null")
  end
end

local function wall_now()
  local f = io.open("/proc/uptime", "r")
  if f then
    local s = f:read("*l")
    f:close()
    if s then
      local up = tonumber(s:match("^(%S+)"))
      if up then return up end
    end
  end
  return os.time()
end

local function answer_line(p, i, n)
  while true do
    print(string.format("%d/%d: %s = ?", i, n, p.text))
    io.write("Answer (q to stop): ")
    local line = io.read("*l")
    if line == nil then return "quit" end
    line = trim(line)
    if line:lower() == "q" then return "quit" end
    local num = tonumber(line)
    if num ~= nil and math.abs(num - p.answer) < 1e-9 then
      return "done"
    end
  end
end

local function answer_raw(p, i, n)
  local exp = p.answer
  local is_int = (exp == math.floor(exp))
  local exp_str = is_int and string.format("%d", exp) or nil
  local buf = ""
  local function draw()
    io.write(string.format("\r\27[K%d/%d: %s = %s",
      i, n, p.text, buf))
    io.flush()
  end
  local function wrong()
    buf = ""
    draw()
  end
  draw()
  while true do
    local ch = io.read(1)
    if ch == nil then return "quit" end
    local b = string.byte(ch)
    if b == 3 or b == 4 then return "quit" end
    if b == 13 or b == 10 then
      if buf ~= "" then
        local num = tonumber(buf)
        if num ~= nil and math.abs(num - exp) < 1e-9 then
          return "done"
        else
          wrong()
        end
      end
    elseif b == 127 or b == 8 then
      buf = buf:sub(1, -2)
      draw()
    elseif b == 27 or b == 91 then
    elseif ch == "q" or ch == "Q" then
      if buf == "" then return "quit" end
      buf = ""
      draw()
    else
      buf = buf .. ch
      draw()
      if exp_str and tonumber(buf) then
        if buf == exp_str then
          return "done"
        elseif #buf >= #exp_str then
          wrong()
        end
      end
    end
  end
end

local function practice(problems)
  local use_raw = stdin_is_tty()
  if use_raw then term_raw() end
  local function run()
    if use_raw then
      io.write("Type answers directly - next problem the instant you're right. 'q' quits.\r\n")
    end
    local n_done = 0
    local start = wall_now()
    for i, p in ipairs(problems) do
      local res
      if use_raw then res = answer_raw(p, i, #problems)
      else res = answer_line(p, i, #problems) end
      if res == "quit" then return "Stopped." end
      n_done = n_done + 1
      clear()
    end
    local total = wall_now() - start
    return string.format("Done. %d problems. Total: %.1fs. Avg: %.1fs/problem.",
      n_done, total, total / n_done)
  end
  local ok, msg = pcall(run)
  term_cooked()
  if not ok then error(msg) end
  print(msg)
end

local function choose_ops()
  print("+================================+")
  print("|           OPERATIONS           |")
  print("+================================+")
  print("|  1) +  Addition                |")
  print("|  2) -  Subtraction             |")
  print("|  3) *  Multiply                |")
  print("|  4) /  Division                |")
  print("|  5) Mixed (all four)           |")
  print("|  6) Custom (pick several)      |")
  print("+================================+")
  while true do
    local s = ask("Choose 1-6", "5")
    if s == "1" then return {"+"} end
    if s == "2" then return {"-"} end
    if s == "3" then return {"*"} end
    if s == "4" then return {":"} end
    if s == "5" then return {"mixed"} end
    if s == "6" then
      local c = ask("Type ops, e.g. +- for add+sub", "+-*/")
      local ops, seen = {}, {}
      for ch in c:gmatch(".") do
        local op = (ch == "/") and ":" or ch
        if (op == "+" or op == "-" or op == "*" or op == ":") and not seen[op] then
          ops[#ops + 1] = op; seen[op] = true
        end
      end
      if #ops > 0 then
        print("Picked: " .. table.concat(ops, " "))
        return ops
      end
      print("Nothing valid. Use characters + - * /")
    else print("Enter 1-6.") end
  end
end

local function choose_neg()
  print("+============================+")
  print("|          NUMBERS           |")
  print("+============================+")
  print("|   1) Disallow negatives    |")
  print("|   2) Allow negatives       |")
  print("+============================+")
  while true do
    local s = ask("Choose 1-2", "1")
    if s == "1" then return false end
    if s == "2" then return true end
    print("Enter 1 or 2.")
  end
end

local function main()
  clear()
  while true do
    print("+================================+")
    print("|           speedmath            |")
    print("+================================+")
    print("|  1) Practice (random)          |")
    print("|  2) Generate file              |")
    print("|  3) Practice from file         |")
    print("|  4) Quit                       |")
    print("+================================+")
    local c = ask("Choose 1-4", "1")
    if c == "4" or c:lower() == "q" then print("Bye!"); break
    elseif c == "1" then
      local ops, neg = choose_ops(), choose_neg()
      local n = ask_number("How many?", "10", 1, 10000)
      if n then
        local ps = {}
        for i = 1, n do ps[i] = gen_problem(ops, neg) end
        clear()
        practice(ps)
      end
    elseif c == "2" then
      local ops, neg = choose_ops(), choose_neg()
      local n = ask_number("How many?", "50", 1, 10000)
      if n then
        local w = ask("Include answers? (y/n)", "n"):lower()
        local with = (w == "y" or w == "yes")
        local fn = ask("Output file", with and "dataset_with_answers.txt" or "dataset.txt")
        local lines = generate_dataset(ops, n, with, neg)
        local f, err = io.open(fn, "w")
        if not f then print("Cannot write: " .. tostring(err))
        else
          for _, l in ipairs(lines) do f:write(l, "\n") end
          f:close()
          print("Wrote " .. #lines .. " to " .. fn)
        end
      end
    elseif c == "3" then
      local fn = ask("File", "dataset.txt")
      local ps, err = load_file(fn)
      if not ps then print("Cannot read: " .. tostring(err))
      elseif #ps == 0 then print("No problems in " .. fn)
      else
        print("Loaded " .. #ps .. " from " .. fn)
        local w = ask("Shuffle? (y/n)", "n"):lower()
        if w == "y" or w == "yes" then shuffle_in_place(ps) end
        clear()
        practice(ps)
      end
    else print("Enter 1-4.") end
  end
end

main()
