curl -s --max-time 5 -o ./clusterstate/clusterstate.json "http://$1s0$2.aws.narasearch.us:8983/solr/zookeeper?detail=true&path=%2Fclusterstate.json"
sed 's/\\n//g' ./clusterstate/clusterstate.json > ./clusterstate/sed.json
sed 's/\\//g' ./clusterstate/sed.json > ./clusterstate/sed_2.json
sed 's/"{"/{"/g' ./clusterstate/sed_2.json > ./clusterstate/sed.json
sed 's/}"}/}}/g' ./clusterstate/sed.json > ./clusterstate/clusterstate.json
