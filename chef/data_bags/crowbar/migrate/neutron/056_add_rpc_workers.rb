def upgrade(ta, td, a, d)
  a["rpc_workers"] = ta["rpc_workers"] unless a.key?("rpc_workers")

  # From 055_add_tunnel_csum.rb
  a["ovs"] ||= {}
  a["ovs"]["tunnel_csum"] = ta["ovs"]["tunnel_csum"]


  return a, d
end

def downgrade(ta, td, a, d)
  a.delete("rpc_workers")

  # From 055_add_tunnel_csum
  if a.key?("ovs")
    a["ovs"].delete("tunnel_csum")
  end

  return a, d
end
