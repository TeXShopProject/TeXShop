-- pdfselectc.lua: run by pdfselectc with texlua (TeX Live), after Claus Gerhardt's pdfselectc.
--
--   pdfselectc selection1 [selection2 ...] filename
--
-- filename is the PDF without .pdf. For each selection, filename-i.pdf is made with the pages
-- it lists: 5:8 is pages 5 to 8; 3:4,6,8:12 is pages 3, 4, 6 and 8 to 12. A page may be listed
-- more than once and in any order. Each page keeps its own size (the crop box, as a PDF viewer
-- shows the page, scaled by the page's UserUnit) and orientation. Links, annotations and the
-- outline of the PDF are not kept.
--
-- The PDF is read with pdfe, the PDF library of LuaTeX, and every selection is checked before
-- any file is made; a wrong selection stops with a message and exit status 1. The pages are put
-- together by luatex (plain, with no packages) in a temporary folder, which is removed afterwards.

local function fail(message)
    io.stderr:write("pdfselectc: ", message, "\n")
    os.exit(1)
end

if #arg < 2 then
    io.stderr:write("usage: pdfselectc selection1 [selection2 ...] filename\n",
                    "  filename is the PDF without .pdf; a selection is like 5:8 or 3:4,6,8:12\n")
    os.exit(2)
end

local base = arg[#arg]
local input = base .. ".pdf"
if not lfs.isfile(input) then fail("cannot find " .. input) end

local document = pdfe.open(input)
if not document then fail(input .. " is not a PDF file that can be read") end
local status = pdfe.getstatus(document)
if status ~= nil and status < 0 then fail(input .. " is protected by a password") end
local count = pdfe.getnofpages(document) or 0
if count < 1 then fail(input .. " has no pages") end

-- A value of the page, or of the page tree above it (MediaBox, CropBox and Rotate are inherited).
local function inherited(page, get, key)
    local node, depth = page, 0
    while node and depth < 64 do
        local value = get(node, key)
        if value ~= nil then return value end
        node = pdfe.getdictionary(node, "Parent")
        depth = depth + 1
    end
end

-- UserUnit (PDF 1.6) is the length of the page's unit in PostScript points, 1 when it is missing.
-- It is an entry of the page itself and is not inherited from the page tree. luatex places a page
-- by its boxes alone and leaves UserUnit out, so the sizes below are scaled here.
local function userunit(page)
    local unit = pdfe.getnumber(page, "UserUnit")
    if type(unit) ~= "number" or not (unit > 0) or unit == math.huge then return 1 end
    return unit
end

-- PDF 1.7 (ISO 32000-1, Annex C) allows pages up to 14400 units on a side.
local largest = 14400
local withunits = false

-- Width and height of each page as a viewer shows it: the crop box inside the media box, turned
-- by the Rotate entry, in PostScript points, and 1 as the unit of the new page. A page that is
-- too large in points keeps its own unit: the sizes are then in that unit, written as UserUnit.
local sizes = {}
local function pagesize(number)
    if sizes[number] then return sizes[number] end
    local page = pdfe.getpage(document, number)
    if not page then fail(string.format("page %d of %s cannot be read", number, input)) end
    local media = inherited(page, pdfe.getbox, "MediaBox")
    if not media then fail(string.format("page %d of %s has no size (MediaBox)", number, input)) end
    local crop = inherited(page, pdfe.getbox, "CropBox") or media
    local llx = math.max(math.min(crop[1], crop[3]), math.min(media[1], media[3]))
    local lly = math.max(math.min(crop[2], crop[4]), math.min(media[2], media[4]))
    local urx = math.min(math.max(crop[1], crop[3]), math.max(media[1], media[3]))
    local ury = math.min(math.max(crop[2], crop[4]), math.max(media[2], media[4]))
    local width, height = urx - llx, ury - lly
    if width <= 0 or height <= 0 then fail(string.format("page %d of %s has an empty crop box", number, input)) end
    local rotate = (inherited(page, pdfe.getinteger, "Rotate") or 0) % 360
    if rotate == 90 or rotate == 270 then width, height = height, width end
    local unit = userunit(page)
    if unit ~= 1 and math.max(width, height) * unit > largest then
        withunits = true
        sizes[number] = {width, height, unit}
    else
        sizes[number] = {width * unit, height * unit, 1}
    end
    return sizes[number]
end

-- Read every selection before making any file.
local selections = {}
for index = 1, #arg - 1 do
    local selection = arg[index]
    local pages = {}
    if selection == "" then fail(string.format("selection %d is empty", index)) end
    for item in (selection .. ","):gmatch("([^,]*),") do
        local first, last = item:match("^%s*(%d+)%s*:%s*(%d+)%s*$")
        if not first then
            first = item:match("^%s*(%d+)%s*$")
            last = first
        end
        if not first then
            fail(string.format("selection %d (%s): \"%s\" is not a page or a range such as 5:8", index, selection, item))
        end
        first, last = tonumber(first), tonumber(last)
        if first > last then
            fail(string.format("selection %d (%s): the range %d:%d goes backwards", index, selection, first, last))
        end
        if first < 1 or last > count then
            fail(string.format("selection %d (%s): %s has pages 1 to %d only", index, selection, input, count))
        end
        for number = first, last do
            pagesize(number)
            pages[#pages + 1] = number
        end
    end
    selections[index] = pages
end

local function bp(value)
    return string.format("%.5fbp", value)
end

local function decimal(value)
    local text = string.format("%.6f", value):gsub("0+$", ""):gsub("%.$", "")
    return text
end

local major, minor = pdfe.getversion(document)
major, minor = tonumber(major) or 1, tonumber(minor) or 4
local lowest = withunits and 6 or 5
if major < 1 or (major == 1 and minor < lowest) then major, minor = 1, lowest end

local luatex = (os.selfdir and (os.selfdir .. "/luatex")) or "luatex"
if not lfs.isfile(luatex) then luatex = "luatex" end

local temporary = os.getenv("TMPDIR")
if not temporary or temporary == "" then temporary = "/tmp" end
temporary = temporary:gsub("/+$", "")
local work = os.tmpdir(temporary .. "/pdfselectc.XXXXXX")
if not work then fail("cannot make a temporary folder in " .. temporary) end

local function cleanup()
    for name in lfs.dir(work) do
        if name ~= "." and name ~= ".." then os.remove(work .. "/" .. name) end
    end
    lfs.rmdir(work)
end

local function copy(from, to)
    local source = io.open(from, "rb")
    if not source then return false end
    local data = source:read("*a")
    source:close()
    local target = io.open(to, "wb")
    if not target then return false end
    local written = target:write(data)
    target:close()
    return written ~= nil
end

local function quote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

if not copy(input, work .. "/in.pdf") then
    cleanup()
    fail("cannot copy " .. input .. " to " .. work)
end

for index, pages in ipairs(selections) do
    local lines = {
        "\\catcode`\\{=1 \\catcode`\\}=2 \\catcode`\\#=6",
        "\\outputmode=1 \\pdfvariable compresslevel=9 \\pdfvariable objcompresslevel=2",
        string.format("\\pdfvariable majorversion=%d \\pdfvariable minorversion=%d", major, minor),
        "\\pdfvariable horigin=0pt \\pdfvariable vorigin=0pt",
    }
    for _, number in ipairs(pages) do
        local width, height, unit = sizes[number][1], sizes[number][2], sizes[number][3]
        local attributes = unit ~= 1 and ("/UserUnit " .. decimal(unit)) or ""
        lines[#lines + 1] = string.format(
            "\\saveimageresource page %d cropbox {in.pdf}\\pagewidth=%s \\pageheight=%s " ..
            "\\pdfvariable pageattr{%s}" ..
            "\\shipout\\hbox{\\useimageresource width %s height %s \\lastsavedimageresourceindex}",
            number, bp(width), bp(height), attributes, bp(width), bp(height))
    end
    lines[#lines + 1] = "\\end"
    local file = io.open(work .. "/select.tex", "w")
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
    local command = string.format("cd %s && %s --interaction=batchmode --halt-on-error --jobname=select select.tex </dev/null >/dev/null 2>&1",
                                  quote(work), quote(luatex))
    local ok = os.execute(command)
    local output = string.format("%s-%d.pdf", base, index)
    if (ok ~= true and ok ~= 0) or not lfs.isfile(work .. "/select.pdf") then
        local log = io.open(work .. "/select.log", "r")
        local text = log and log:read("*a") or ""
        if log then log:close() end
        local problem = text:match("\n(! [^\n]*)") or "luatex did not make the file"
        cleanup()
        fail(string.format("%s was not made: %s", output, problem))
    end
    if not copy(work .. "/select.pdf", output) then
        cleanup()
        fail("cannot write " .. output)
    end
    os.remove(work .. "/select.pdf")
    os.remove(work .. "/select.log")
end

cleanup()
