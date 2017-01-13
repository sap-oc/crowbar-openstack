def upgrade(ta, td, a, d)
  unless a.key? "use_l2pop"
    # Only enable it if DVR is used
    a["use_l2pop"] = true
  end

  return a, d
end

def downgrade(ta, td, a, d)
  unless ta.key? "use_l2pop"
    a.delete("use_l2pop")
  end

  return a, d
end
