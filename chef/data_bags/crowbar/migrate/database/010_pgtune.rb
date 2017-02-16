def upgrade(ta, td, a, d)
  a["postgresql"]["config_pgtune"] ||= {}
  unless a["postgresql"]["config_pgtune"].key?("max_connections")
    a["postgresql"]["config_pgtune"]["max_connections"] = a["postgresql"]["config"]["max_connections"]
  end
  a["postgresql"]["config"].delete("max_connections")

  return a, d
end

def downgrade(ta, td, a, d)
  if ta["postgresql"]["config"].key?("max_connections")
    a["postgresql"]["config"]["max_connections"] = a["postgresql"]["config_pgtune"]["max_connections"]
    a["postgresql"]["config_pgtune"].delete("max_connections")
    a["postgresql"].delete("config_pgtune") if a["postgresql"]["config_pgtune"].empty?
  end

  return a, d
end
