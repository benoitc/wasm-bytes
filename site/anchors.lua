-- Gives every section heading a link to itself, so that any part of a page
-- can be linked. The heading keeps the identifier pandoc gave it, the same
-- one GitHub uses, so links written for GitHub keep working on the site.
function Header(h)
  if h.level < 2 or h.identifier == "" then
    return nil
  end
  h.content:insert(pandoc.Link({pandoc.Str("#")}, "#" .. h.identifier, "",
    pandoc.Attr("", {"anchor"}, {{"aria-label", "Link to this section"}})))
  return h
end
