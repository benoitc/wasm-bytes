-- Rewrites the links of a repository page for the site. A link to a page the
-- site renders goes to its HTML; README.md is the site's index. A link to
-- anything else in the repository, such as a source file or a recorded
-- reply, goes to it on GitHub. Images stay relative: the build copies them.
-- A full link to the published site, which the README needs on GitHub,
-- becomes a link within the site, so a local build stays local.
-- Links in raw HTML are rewritten the same way.
local function is_page(path)
  return path == "README.md" or path == "trials/README.md"
      or path:match("^doc/[^/]+%.md$") ~= nil
end

function Pandoc(doc)
  local source = pandoc.utils.stringify(doc.meta.source)
  local repo = pandoc.utils.stringify(doc.meta.repo)
  local dir = pandoc.path.directory(source)
  local owner, name = repo:match("github%.com/([^/]+)/([^/]+)")
  local site = "https://" .. owner .. ".github.io/" .. name .. "/"
  local up = ""
  if dir ~= "." and dir ~= "" then
    up = string.rep("../", #pandoc.path.split(dir))
  end

  local function resolve(target)
    if target:sub(1, #site) == site then
      local rest = target:sub(#site + 1)
      return up .. (rest == "" and "index.html" or rest)
    end
    if target:match("^%a[%w+.-]*:") or target:match("^#") then
      return target
    end
    local path, frag = target:match("^([^#]*)(#?.*)$")
    local full = pandoc.path.normalize(pandoc.path.join({dir, path}))
    if is_page(full) then
      local html = path:gsub("README%.md$", function()
        return full == "README.md" and "index.html" or "README.html"
      end):gsub("%.md$", ".html")
      return html .. frag
    end
    local kind = path:match("/$") and "tree" or "blob"
    return repo .. "/" .. kind .. "/main/" .. full:gsub("^%./", "") .. frag
  end

  -- Links written as HTML inside a page, such as the DX-Ball flow, get the
  -- same treatment as Markdown links.
  local function rewrite_html(raw)
    if raw.format ~= "html" then
      return nil
    end
    raw.text = raw.text:gsub('href="([^"]*)"', function(target)
      return 'href="' .. resolve(target) .. '"'
    end)
    return raw
  end

  return doc:walk({
    Link = function(link)
      link.target = resolve(link.target)
      return link
    end,
    RawBlock = rewrite_html,
    RawInline = rewrite_html,
  })
end
