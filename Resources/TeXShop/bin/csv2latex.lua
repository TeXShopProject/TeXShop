-- csv2latex.lua: run by csv2latex with texlua (TeX Live), after csv2latex 1.2 (Ruby) by
-- Tom Counsell <tom@counsell.org> (2005) and Alan Munn <amunn@msu.edu> (2009, 2010).
-- Licensed under the GPL, as the Ruby script was.
--
--   texlua csv2latex.lua [tablestyle] < cells > table
--
-- Reads spreadsheet cells (rows separated by CR, LF or CRLF, cells by tabs) from standard input
-- and writes them as a LaTeX table to standard output. tablestyle is cells, simple (the default),
-- booktabs or longtable. & $ # and % in the cells get a backslash. When there is no row at all,
-- nothing is written.
--
-- The output is that of the Ruby script, byte for byte: as there, trailing empty rows and trailing
-- empty cells of a row are left out, the first row is the header, and a style that is not one of
-- the four gets a tabular without the header. The text is read as bytes, so any encoding that
-- keeps tab, CR, LF and & $ # % as in ASCII (UTF-8, Mac Roman, Shift JIS ...) comes out unchanged.

-- Splits s at each sep (one character), as Ruby's String#split with a string: the empty fields at
-- the end are dropped, so an empty string gives no field.
local function split(s, sep)
    local fields, start = {}, 1
    while true do
        local at = string.find(s, sep, start, true)
        if not at then
            fields[#fields + 1] = string.sub(s, start)
            break
        end
        fields[#fields + 1] = string.sub(s, start, at - 1)
        start = at + 1
    end
    while #fields > 0 and fields[#fields] == "" do
        fields[#fields] = nil
    end
    return fields
end

local function escape_latex(s)
    return (string.gsub(s, "([&$#%%])", "\\%1"))
end

local function row(cells)
    local escaped = {}
    for i, cell in ipairs(cells) do
        escaped[i] = escape_latex(cell)
    end
    return table.concat(escaped, " & ") .. " \\\\"
end

local function puts(s)
    io.write(s or "", "\n")
end

local text = io.read("a") or ""
text = string.gsub(string.gsub(text, "\r\n", "\r"), "\n", "\r")
local lines = split(text, "\r")
if #lines == 0 then
    os.exit(0)
end
local columns = 0
for i, line in ipairs(lines) do
    lines[i] = split(line, "\t")
    if #lines[i] > columns then
        columns = #lines[i]
    end
end
local header = table.remove(lines, 1)
local hstyle = arg[1] or "simple"
local spec = string.rep("l", columns)

if hstyle == "longtable" then
    puts("\\begin{longtable}{" .. spec .. "}")
    puts(row(header))
    puts("\\endfirsthead")
    puts(row(header))
    puts("\\endhead")
    -- One backslash at the end of the line, as in the Ruby script.
    puts("\\multicolumn{" .. columns .. "}{r}{{Continued\\ldots}} \\")
    puts("\\endfoot")
    puts("\\hline")
    puts("\\endlastfoot")
    puts()
elseif hstyle ~= "cells" then
    puts("\\begin{tabular}{" .. spec .. "}")
    puts()
end
if hstyle == "booktabs" then
    puts("\\toprule")
    puts(row(header))
    puts("\\midrule")
end
if hstyle == "simple" or hstyle == "cells" then
    puts(row(header))
end
for _, cells in ipairs(lines) do
    puts(row(cells))
end
puts()
if hstyle == "booktabs" then
    puts("\\bottomrule")
end
if hstyle == "longtable" then
    puts("\\end{longtable}")
elseif hstyle ~= "cells" then
    puts("\\end{tabular}")
end
