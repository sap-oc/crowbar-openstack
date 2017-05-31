# Copyright 2014 SUSE
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

unless node[:cinder][:ha][:enabled]
  log "HA support for cinder is disabled"
  return
end

log "HA support for cinder is enabled"

cluster_vhostname = CrowbarPacemakerHelper.cluster_vhostname(node)

admin_net_db = Chef::DataBagItem.load("crowbar", "admin_network").raw_data
cluster_admin_ip = admin_net_db["allocated_by_name"]["#{cluster_vhostname}.#{node[:domain]}"]["address"]

haproxy_loadbalancer "cinder-api" do
  address node[:cinder][:api][:bind_open_address] ? "0.0.0.0" : cluster_admin_ip
  port node[:cinder][:api][:bind_port]
  use_ssl (node[:cinder][:api][:protocol] == "https")
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "cinder", "cinder-controller", "api")
  action :nothing
end.run_action(:create)

# Wait for all nodes to reach this point so we know that all nodes will have
# all the required packages installed before we create the pacemaker
# resources
crowbar_pacemaker_sync_mark "sync-cinder_before_ha"

# Avoid races when creating pacemaker resources
crowbar_pacemaker_sync_mark "wait-cinder_ha_resources"

rabbit_settings = fetch_rabbitmq_settings
transaction_objects = []

api_primitive = "cinder-api"
pacemaker_primitive api_primitive do
  agent node[:cinder][:ha][:api_ra]
  op node[:cinder][:ha][:op]
  action :update
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end
transaction_objects << "pacemaker_primitive[#{api_primitive}]"

scheduler_primitive = "cinder-scheduler"
pacemaker_primitive scheduler_primitive do
  agent node[:cinder][:ha][:scheduler_ra]
  op node[:cinder][:ha][:op]
  action :update
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end
transaction_objects << "pacemaker_primitive[#{scheduler_primitive}]"

group_name = "g-cinder-controller"
pacemaker_group group_name do
  members [api_primitive, scheduler_primitive]
  action :update
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end
transaction_objects << "pacemaker_group[#{group_name}]"

clone_name = "cl-#{group_name}"
pacemaker_clone clone_name do
  rsc group_name
  meta ({
    "clone-max" => CrowbarPacemakerHelper.num_corosync_nodes(node),
    "interleave" => "true",
  })
  action :update
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end
transaction_objects << "pacemaker_clone[#{clone_name}]"

location_name = openstack_pacemaker_controller_only_location_for clone_name
transaction_objects << "pacemaker_location[#{location_name}]"

pacemaker_transaction "cinder controller" do
  cib_objects transaction_objects
  # note that this will also automatically start the resources
  action :commit_new
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

crowbar_pacemaker_order_only_existing "o-#{clone_name}" do
  ordering ["postgresql", "#{rabbit_settings[:pacemaker_resource]}", "cl-keystone", clone_name]
  score "Optional"
  action :create
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

crowbar_pacemaker_sync_mark "create-cinder_ha_resources"
