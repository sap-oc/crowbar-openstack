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

haproxy_loadbalancer "heat-api" do
  address "0.0.0.0"
  port node[:heat][:api][:port]
  use_ssl (node[:heat][:api][:protocol] == "https")
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "heat", "heat-server", "api_port")
  action :nothing
end.run_action(:create)

haproxy_loadbalancer "heat-api-cfn" do
  address "0.0.0.0"
  port node[:heat][:api][:cfn_port]
  use_ssl (node[:heat][:api][:protocol] == "https")
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "heat", "heat-server", "cfn_port")
  action :nothing
end.run_action(:create)

haproxy_loadbalancer "heat-api-cloudwatch" do
  address "0.0.0.0"
  port node[:heat][:api][:cloud_watch_port]
  use_ssl (node[:heat][:api][:protocol] == "https")
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "heat", "heat-server", "cloud_watch_port")
  action :nothing
end.run_action(:create)

# Wait for all nodes to reach this point so we know that all nodes will have
# all the required packages installed before we create the pacemaker
# resources
crowbar_pacemaker_sync_mark "sync-heat_before_ha"

# Avoid races when creating pacemaker resources
crowbar_pacemaker_sync_mark "wait-heat_ha_resources"

primitives = []
transaction_objects = []

["engine", "api", "api_cfn", "api_cloudwatch"].each do |service|
  primitive_name = "heat-#{service}".gsub("_","-")
  pacemaker_primitive primitive_name do
    agent node[:heat][:ha][service.to_sym][:agent]
    op node[:heat][:ha][service.to_sym][:op]
    action :update
    only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
  end
  primitives << primitive_name
  transaction_objects << "pacemaker_primitive[#{primitive_name}]"
end

group_name = "g-heat"

pacemaker_group group_name do
  members primitives
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

pacemaker_transaction "heat server" do
  cib_objects transaction_objects
  # note that this will also automatically start the resources
  action :commit_new
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

crowbar_pacemaker_order_only_existing "o-#{clone_name}" do
  ordering ["postgresql", "rabbitmq", "cl-keystone", "cl-g-nova-controller", clone_name]
  score "Optional"
  action :create
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

crowbar_pacemaker_sync_mark "create-heat_ha_resources"
