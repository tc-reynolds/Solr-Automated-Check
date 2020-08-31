shard=$(( $1 % 2 ))
node=$1
if [ $shard = 0 ]; then
shard=2
fi
if jq -e . >/dev/null 2>&1 <<< $(cat ./clusterstate/clusterstate.json); then
   cat ./clusterstate/clusterstate.json | jq ".znode.data.collection1.shards.shard${shard}.replicas.core_node${node}.state" | sed 's/"//g' 
else
   echo "Failed to parse JSON, bad server state."
    
fi

