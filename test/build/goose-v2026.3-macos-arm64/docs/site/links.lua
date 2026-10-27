-- Pandoc filter for the documentation site (build.py).
--
-- The markdown files link to each other as they lie in the repository, so
-- that they read on GitHub: `docs/tutorial.md`, `../samples/README.md`,
-- `01_tour.goose`. The site keeps the repository's layout and turns each
-- of those into the page built from it.

local function rewrite(target)
  if target:match("^%a[%w+.-]*:") then return target end   -- http:, mailto:, ...
  local path, frag = target:match("^([^#]*)(#?.*)$")
  if path == "" then return target end
  local dir, file = path:match("^(.-)([^/]*)$")
  if file == "README.md" then
    file = "index.html"
  elseif file:match("%.md$") then
    file = file:gsub("%.md$", ".html")
  elseif file:match("%.goose$") then
    file = file .. ".html"
  elseif file == "LICENSE" then
    file = "LICENSE.html"
  end
  return dir .. file .. frag
end

function Link(el)
  el.target = rewrite(el.target)
  return el
end

-- The files carry a <details> table of contents for GitHub, which the
-- site's sidebar replaces. The gfm reader hands it over as raw HTML blocks
-- around a bullet list; drop everything from <details> to </details> when
-- the summary is the table of contents.
function Pandoc(doc)
  local out = {}
  local blocks = doc.blocks
  local i = 1
  while i <= #blocks do
    local b = blocks[i]
    local is_toc = false
    if b.t == "RawBlock" and b.text:match("<details>") then
      if b.text:match("Table of contents") then
        is_toc = true
      else
        local n = blocks[i + 1]
        is_toc = n ~= nil and n.t == "RawBlock" and n.text:match("Table of contents") ~= nil
      end
    end
    if is_toc then
      while i <= #blocks and not (blocks[i].t == "RawBlock" and blocks[i].text:match("</details>")) do
        i = i + 1
      end
      i = i + 1
    else
      table.insert(out, b)
      i = i + 1
    end
  end
  doc.blocks = out
  return doc
end
