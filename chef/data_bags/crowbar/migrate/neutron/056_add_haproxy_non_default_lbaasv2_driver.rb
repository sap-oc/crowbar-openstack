def upgrade(ta, td, a, d)
  unless a["f5"].key?("add_haproxy_as_non_default")
    a["f5"]["add_haproxy_as_non_default"] = ta["f5"]["add_haproxy_as_non_default"]
  end

  return a, d
end

def downgrade(ta, td, a, d)
  unless ta["f5"].key?("add_haproxy_as_non_default")
    a["f5"].delete("add_haproxy_as_non_default")
  end

  return a, d
end
