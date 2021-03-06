#!/bin/bash
#set -x
set -euo pipefail

# This script is the entrypoint to the image.

# ====================
# Environment variables are used to customize operation

# There is a single image for both master node and compute node
# setup. When OVN_MASTER is true, start the master daemons
# in addition to the node daemons
ovn_master=${OVN_MASTER:-"false"}

# hostname is the host's hostname when using host networking,
# otherwise it is the container ID (useful for debugging).
ovn_host=$(hostname)

# # The ovs user id 
# ovs_user_id=${OVS_USER_IDi:-root:root}

# # ovs options
# ovs_options=${OVS_OPTIONS:-""}

# Cluster's internal network cidr
net_cidr=${OVN_NET_CIDR:-"10.128.0.0/14"}
# Cluster's service ip subnet
svc_cidr=${OVN_SVC_CIDR:-"172.30.0.0/16"}

# ovn north and south databases
ovn_nbdb=${OVN_NORTH:-""}
ovn_sbdb=${OVN_SOUTH:-""}
# Used to test for ovn-northd coming up
ovn_nbdb_test=$(echo ${ovn_nbdb} | sed 's;//;;')

# kubernetes api server configuration
k8s_api=${K8S_APISERVER:-""}
k8s_token=${K8S_TOKEN:-""}

# ovn-northd - /etc/sysconfig/ovn-northd
ovn_northd_opts=${OVN_NORTHD_OPTS:-"--db-nb-sock=/var/run/openvswitch/ovnnb_db.sock --db-sb-sock=/var/run/openvswitch/ovnsb_db.sock"}

# ovn-controller
#OVN_CONTROLLER_OPTS="--ovn-controller-log=-vconsole:emer --vsyslog:err -vfile:info"
ovn_controller_opts=${OVN_CONTROLLER_OPTS:-"--ovn-controller-log=-vconsole:emer"}

# =========================================

# Master must be up before the nodes can come up.
# This waits for northd to come up
wait_for_northdb () {
  # Wait for ovn-northd to come up
  trap 'kill $(jobs -p); exit 0' TERM
  retries=0
  while true; do
    # northd is up when this works
    ovn-nbctl --db=${ovn_nbdb_test} show > /dev/null
    if [[ $? != 0 ]] ; then
      echo "info: Waiting for ovn-northd to come up, waiting 10s ..." 2>&1
      sleep 10 & wait
      (( retries += 1 ))
    else
      break
    fi
    if [[ "${retries}" -gt 40 ]]; then
      echo "error: ovn-northd did not come up, exiting" 2>&1
      exit 1
    else
      echo "ovn-northd came up in ${retries} 10sec tries"
    fi
  done
}

display () {
  echo ${ovn_host}
  date
  if [[ ${ovn_master} = "true" ]]
  then
    echo "==================== ovnkube-master =================== "
    echo "====================== ovnnb_db.pid"
    if [[ -f /var/run/openvswitch/ovnnb_db.pid ]]
    then
      cat /var/run/openvswitch/ovnnb_db.pid
    fi
    echo "====================== ovnsb_db.pid"
    if [[ -f /var/run/openvswitch/ovnsb_db.pid ]]
    then
      cat /var/run/openvswitch/ovnsb_db.pid
    fi
    echo "====================== ovs-vswitchd.pid"
    if [[ -f /var/run/openvswitch/ovs-vswitchd.pid ]]
    then
      cat /var/run/openvswitch/ovs-vswitchd.pid
    fi
    echo "====================== ovsdb-server.pid"
    if [[ -f /var/run/openvswitch/ovsdb-server.pid ]]
    then
      cat /var/run/openvswitch/ovsdb-server.pid
    fi
    echo "====================== ovsdb-server-nb.log"
    if [[ -f /var/log/openvswitch/ovsdb-server-nb.log ]]
    then
      cat /var/log/openvswitch/ovsdb-server-nb.log
    fi
    echo "====================== ovsdb-server-sb.log "
    if [[ -f /var/log/openvswitch/ovsdb-server-sb.log ]]
    then
      cat /var/log/openvswitch/ovsdb-server-sb.log
    fi
    echo "====================== ovn-northd.pid"
    if [[ -f /var/run/openvswitch/ovn-northd.pid ]]
    then
      cat /var/run/openvswitch/ovn-northd.pid
    fi
    echo " "
    echo "====================== ovn-northd.log"
    if [[ -f /var/log/openvswitch/ovn-northd.log ]]
    then
      cat /var/log/openvswitch/ovn-northd.log
    fi
    echo " "
    echo "====================== ovnkube-master.pid"
    if [[ -f /var/run/openvswitch/ovnkube-master.pid ]]
    then
      cat /var/run/openvswitch/ovnkube-master.pid
    fi
    echo " "
    echo "====================== ovnkube-master.log"
    if [[ -f /var/log/openvswitch/ovnkube-master.log ]]
    then
      cat /var/log/openvswitch/ovnkube-master.log
    fi
  fi
  echo " "
  echo "==================== ovnkube =================== "
  echo "====================== ovn-controller.pid"
  if [[ -f /var/run/openvswitch/ovn-controller.pid ]]
  then
    cat /var/run/openvswitch/ovn-controller.pid
  fi
  echo " "
  echo "====================== ovn-controller.log"
  if [[ -f /var/log/openvswitch/ovn-controller.log ]]
  then
    cat /var/log/openvswitch/ovn-controller.log
  fi
  echo " "
  echo "====================== ovnkube.pid"
  if [[ -f /var/run/openvswitch/ovnkube.pid ]]
  then
    cat /var/run/openvswitch/ovnkube.pid
  fi
  echo " "
  echo "====================== ovnkube.log"
  if [[ -f /var/log/openvswitch/ovnkube.log ]]
  then
    cat /var/log/openvswitch/ovnkube.log
  fi
  echo " "
  echo "====================== ovn-k8s-cni-overlay.log"
  if [[ -f /var/log/openvswitch/ovn-k8s-cni-overlay.log ]]
  then
    cat /var/log/openvswitch/ovn-k8s-cni-overlay.log
  fi
}

setup_cni () {
  # Take over network functions on the node
  # rm -Rf /etc/cni/net.d/*
  rm -Rf /host/opt/cni/bin/ovn-k8s-cni-overlay
  cp -Rf /opt/cni/bin/* /host/opt/cni/bin/
  cp -f  /usr/libexec/cni/loopback /host/opt/cni/bin/
}

start_ovn () {
  echo " ==================== hostname: ${ovn_host} "

echo OVN_NORTH $OVN_NORTH
echo OVN_SOUTH $OVN_SOUTH
echo OVN_NET_CIDR $OVN_NET_CIDR
echo OVN_SVC_CIDR $OVN_SVC_CIDR
echo K8S_APISERVER $K8S_APISERVER
echo K8S_TOKEN $K8S_TOKEN

  setup_cni

# # start ovsdb-server
# /usr/share/openvswitch/scripts/ovs-ctl \
#   --no-ovs-vswitchd --no-monitor --system-id=random \
#   --ovs-user=${ovs_user_id} \
#   start ${ovs_options}

# # start ovs-vswitchd
# /usr/share/openvswitch/scripts/ovs-ctl \
#   --no-ovsdb-server --no-monitor --system-id=random \
#   --ovs-user=${ovs_user_id} \
#   start ${ovs_options}

  if [[ ${ovn_master} = "true" ]]
  then
    # ovn-northd - master node only
    echo "=============== start ovn-northd ========== MASTER ONLY"
    /usr/share/openvswitch/scripts/ovn-ctl start_northd \
      --db-nb-addr=${ovn_nbdb} --db-sb-addr=${ovn_sbdb} \
      --db-nb-sock=/var/run/openvswitch/ovnnb_db.sock \
      --db-sb-sock=/var/run/openvswitch/ovnsb_db.sock

    # ovn-master - master node only
#   wait_for_northdb

    echo "=============== start ovn-master ========== MASTER ONLY"
    /usr/bin/ovnkube \
      --init-master ${ovn_host} --net-controller \
      --cluster-subnet ${net_cidr} --service-cluster-ip-range=${svc_cidr} \
      --k8s-token=${k8s_token} --k8s-apiserver=${k8s_api} \
      --nb-address=${ovn_nbdb} --sb-address=${ovn_sbdb} \
      --nodeport \
      --pidfile /var/run/openvswitch/ovnkube-master.pid \
      --logfile /var/log/openvswitch/ovnkube-master.log &

  fi

  # ovn-controller - all nodes
  echo "=============== start ovn-controller"
  /usr/share/openvswitch/scripts/ovn-ctl --no-monitor start_controller \
    ${ovn_controller_opts}

  # ovn-node - all nodes
#   wait_for_northdb

  echo  "=============== start ovn-node"
  /usr/bin/ovnkube --init-node ${ovn_host} \
      --cluster-subnet ${net_cidr} --service-cluster-ip-range=${svc_cidr} \
      --k8s-token=${k8s_token} --k8s-apiserver=${k8s_api} \
      --nb-address=${ovn_nbdb} --sb-address=${ovn_sbdb} \
      --nodeport \
      --init-gateways \
      --pidfile /var/run/openvswitch/ovnkube.pid \
      --logfile /var/log/openvswitch/ovnkube.log &

  echo "=============== done starting daemons ================="

# Let it settle
  sleep 4

# display results
  display
}

echo "================== ovnkube.sh ================"

# Start the ovn daemons
# daemons come up in order
# ovs-db-server  - all nodes  - done in another daemonset
# ovs-vswitchd   - all nodes  - done in another daemonset
# ovn-northd     - master node only
# ovn-master     - master node only
# ovn-controller - all nodes
# ovn-node       - all nodes

start_ovn

# keep the container alive
tail -f /dev/null

exit 0
