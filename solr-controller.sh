#!/bin/bash


solr_reboot(){
  send_mail $1 s
  echo "Reboot initiating on ${env}s0${1}...."
  ssh -i /your/password user@${env}s0$1 sudo reboot
  echo "${env}s0${1} $(date +%s)" >> ./docs/solr_reboots.txt
}
#
api_reboot(){
  send_mail $1 a
  echo "Reboot initiating on ${env}a0${1}...."
  ssh -i /your/password user@${env}a0$1 sudo reboot
  echo "${env}a0${1}" >> ./docs/api_reboots.txt
}

time_calc(){
  last_reboot_ts=$(tac ./docs/solr_reboots.txt | grep -m1 ${env}s0${1} | grep -o ' [0-9]*')
  local current_ts=$(date +%s)
  #echo $last_reboot_ts
  if [ "$last_reboot_ts" -gt "0" ]; then
   echo $(($current_ts - $last_reboot_ts))
  else
   echo "$current_ts"
  fi   
}

send_mail(){
  SEND_MAIL=2
  echo "Reboot issued for: ${env}${2}0${1}. Timestamp: $(date)" >> ./docs/mail.txt
}
check_shard_doc(){
 local shard_num=$1
 local first_node_doc=$(( $first_node + $shard_num ))
 set_health_check_node $first_node_doc
 printf "\nfirst_node_doc: ${first_node_doc}"
 local first_doc=$( document_count_check "$first_node_doc" )
 printf "\n__first_doc___\n"
 printf "${first_doc}"
 for i in $(seq $first_node_doc 2 $last_node)
 do
  set_health_check_node $i
  local next_doc=$( document_count_check $i)
  if [ "$next_doc" != "$first_doc" ]; then
   local diff_of_doc=$(( $first_doc - $next_doc ))
   echo "Inconsistent doc between Node ${first_node_doc} and Node ${i}, difference of ${diff_of_doc} " 
   echo "Inconsistent doc between Node ${first_node_doc} and Node ${i}, difference of ${diff_of_doc} " >> mail.txt
  fi
 done
}
document_count_check(){
 printf "\nDocument Count Check Called!"
 curl -silent --max-time 5 $SOLR_HEALTHCHECK > ./solr_status/${env}s0${1}_status.txt
 local status=$( cat ./solr_status/${env}s0${1}_status.txt )
# printf "\n______________status____________________\n"
# printf "status: ${status}" 
 local doc_count=$( echo $status | grep -o -P '(?<=numDocs">).*?(?=</int>)' | head -1 )
 printf "\nWithin document_count_check: ${doc_count}\n"
 echo $doc_count
}
perform_health_check(){
 curl -silent --max-time 5 $SOLR_HEALTHCHECK > ./solr_status/${env}s0${1}_status.txt
 local status=$( cat ./solr_status/${env}s0${1}_status.txt ) 
 local stat_return=$( echo $status | grep -o -P '(?<=status">).*?(?=</int>)' | head -1 )
 echo $stat_return
}

check_state(){
 local i 
 active_nodes=0
 set_health_check_node $first_node 
 echo "Health Check Node set..."
 if [ "$solr_responsive" == "0" ]; then
  for i in $(seq 1 $num_nodes)
   do
    local curr_node=$(( $i + $first_node - 1 ))
    SOLR_HEALTHCHECK="http://${env}s0${curr_node}.aws.nac.nara.gov:8983/solr/admin/cores?action=STATUS"
    echo "Checking node ${curr_node}...."
    local state=$( ./check_state.sh $(( $i )) )
    if [ $state == "active" ]; then
      echo "Node $curr_node is active."
      active_nodes=$(( $active_nodes + 1 ))
    fi
    if [ $state == "recovering" ]; then
      echo "Node $curr_node is recovering..."
    fi
    if [ $state == "down" ]; then
      echo "Node $curr_node is down, rebooting...." 
      check_reboot $(( $curr_node ))
      check_node $curr_node
    fi
   done
   check_api_disconnect
 fi
}
check_api_disconnect(){
  local i
  echo "Checking for API disconnect...num active nodes: $active_nodes, num nodes: $num_nodes"
  if [ "$active_nodes" == "$num_nodes" ]; then
    echo "$api_unavailable"
    if [ "$api_unavailable" == "unavailable" ]; then
      echo "API disconnect detected, issuing system refresh"
      rolling_refresh
    fi
  fi
}
rolling_refresh(){
 solr_refresh
 api_refresh
}
solr_refresh(){
 local pair=0
 local i
 for i in $(seq $first_node 2 $last_node)
  do
    echo "Checking reboot for $i and $(( i + 1 ))..."
    check_reboot $i
    check_reboot $((i + 1))
    set_health_check_node $first_node
    sleep $sleep_time
    check_node $i
    check_node $((i +1))
  done
}
api_refresh(){
 local i
 for i in $( seq $first_api_node $(( num_api + first_api_node - 1 )) )
  do
    echo "Reboot! $i"
    api_reboot $i
    sleep $sleep_time
    check_api $i
  done
}
check_api(){
 ssh -i /your/password user@${env}a0$1 exit
 if [ $? -eq 0 ]; then
    echo "${env}a0${1} is back online...moving on."
 else
    echo "API Server unavailable, sleeping for 30s and pinging again"
    sleep 30s
    check_api $1
 fi 
}
check_node(){
  set_health_check_node $first_node
  ./parse_json.sh $env $health_check_node
  local state=$( ./check_state.sh $(( $1 - $first_node + 1 )) )
  echo "Check Node $1 state: $state"
  if [ $state == "active" ]; then
    echo "Node $1 is active."
  fi
  if [ $state == "recovering" ]; then
    echo "Node $1 is recovering...will check again in $sleep_time"
    sleep $sleep_time
    check_node $1
  fi
  if [ $state == "down" ]; then
    echo "Node $1 is still down...will check again in $sleep_time."
    sleep $sleep_time
    check_node $1
  fi
  if [ $state == "null" ]; then
    echo "Node State null. Awaiting more information before action."
    sleep $sleep_time
    check_node $1
  fi
     
}
set_health_check_node(){
 health_check_node=$1
 SOLR_HEALTHCHECK="http://${env}s0${health_check_node}.aws.nac.nara.gov:8983/solr/admin/cores?action=STATUS"
 solr_responsive=$( perform_health_check $health_check_node)
 if [ -z "$solr_responsive" ]; then
   if [ $1 -lt $last_node ]; then
     echo "Node ${1} unable to provide healthcheck, checking other nodes for healthcheck..."
     set_health_check_node $(( $1 + 1 ))
     else
        echo "All solr servers unresponsive."
        exit 2
   fi
 fi
 if [ "$solr_responsive" == "0" ]; then
   echo "Node performing health_check: ${health_check_node}"
   ./parse_json.sh $env $health_check_node
   echo "Json recieved from Solr...."
 fi
}
#The only function that calls Solr reboot to s
check_reboot(){
 local node=$1
 delta=$( time_calc $node )
 total_time=$( printf '%dd:%dh:%dm:%ds\n' $(($delta/86400/3600)) $(($delta%86400/3600)) $(($delta%3600/60)) $(($delta%60)) )
 echo "Last reboot: $total_time"
 echo "Time since last reboot: $delta"
 echo "Reboot threshold: $reboot_threshold"
 if [ $delta -gt $reboot_threshold ]; then
    echo "Reboot function called..." 
    solr_reboot $node
 else
    echo "Last reboot has occurred too recently. Cancelling reboot for $node ...."
    echo "Last reboot on ${env}s0$i ${total_time} ago seems unsuccessful. Manual intervention required." >> ./docs/mail.txt
 fi
}

#First Function called to start Solr checks
solr_check(){
 echo "" > ./docs/mail.txt

 local node=$1
 check_state $node
 #Check whether the document counts are accurate across shards
 check_shard_doc 0
 check_shard_doc 1
}

reboot_threshold=7200
if [ "$1" == "prod" ]; then
 env="p"
 first_api_node=1
 first_node=1
 num_nodes=6
 num_api=4
 echo "Checking Production Environment"
 echo "env; $env : num_nodes; $num_nodes : num_api; $num_api "
fi
if [ "$1" == "dev" ]; then
 env="d"
 first_node=5
 first_api_node=3
 num_nodes=4
 num_api=1
 echo "Checking Dev Environment"
 sleep 1s
 echo "env; $env : num_nodes; $num_nodes : num_api; $num_api "
 sleep 2s
fi
last_node=$(( $first_node + $num_nodes - 1 ))
sleep_time=1m
SEND_MAIL=0
api_unavailable=$2

solr_check $first_node
echo "All solr servers checked...."
if [ "$SEND_MAIL" != "0" ]; then
    echo "Emailing actions and status...."
    ./parse_json.sh $env $health_check_node 
    sendmail "$RECIPIENTS" <<EOF
subject:Solr Status
from: native@mail-client.com

$(cat ./docs/mail.txt)
Current States of Solr Servers:
Node 1: $(./check_state.sh 1)
Node 2: $(./check_state.sh 2)
Node 3: $(./check_state.sh 3)
Node 4: $(./check_state.sh 4)
Node 5: $(./check_state.sh 5)
Node 6: $(./check_state.sh 6)
EOF
   exit 2
fi

echo "Job Finished. No issues detected."
