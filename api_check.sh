check_api(){
 for api_term in "${api_terms[@]}"
 do
  echo "Term searched on: ${api_term}"
  make_api_call
  parse_api_response
  first_total=$curr_total
  first_response_code=$curr_response_code
  echo "First call made, total: $first_total, response: $first_response_code"
  sleep $sleep_time
  for i in $(seq 1 $num_check)
  do
   make_api_call
   parse_api_response
   echo "$i calls made, total: $curr_total, response: $curr_response_code"
   if [ "$curr_response_code" == "200" ]; then
    echo "200 response received...comparing totals..."
    check_response_code
   else
    echo "API unresponsive...."
    api_unavailable=$(( ${api_unavailable} + 1 ))
   fi
   sleep $sleep_time 
  done
 done
}
make_api_call(){
  api_call="${api_env}${api_term}"
  curl -m 5 -s -o $api_response $api_call 
}
parse_api_response(){
  curr_total=$( cat $api_response | grep total | grep -o "$num_regex" | head -1 )
  curr_response_code=$( cat $api_response | grep @status | grep -o "$num_regex" )
}
check_response_code(){
 if [ "$curr_total" != "$first_total" ]; then
    api_inconsistent=$(( ${api_inconsistent} + 1 ))
    local different_totals=$(( $curr_total - $first_total ))
    echo "Difference of ${different_totals}, Curr Total: ${curr_total}, First Total: ${first_total}"
    if [ "$curr_total" -gt "$first_total" ]; then
      first_total=$curr_total
      echo "Replacing first_total with higher value"
    fi
    else
      if [ ${i} -lt $num_check ]; then
       echo "Results matched. Next call :)"
      else
       echo "Results matched, final call made!"
      fi
   fi
   
}
check_errors(){
 echo "API inconsistent: $api_inconsistent, API unavailable: $api_unavailable"
 echo "Total Calls Made: ${total_check} "
 percent_error=$( bc <<< "scale=2;${api_unavailable}/${total_check}*100" ) 
 percent_inconsistent=$( bc <<< "scale=2;${api_inconsistent}/${total_check}*100" ) 
 if [ "$api_inconsistent" != "0" ]; then
  echo "Document inconsistency suspected, checking solr docs." 
  #source ./document_check.sh
 fi
 if [ "$api_unavailable" -gt "$((num_check / 2))" ]; then
  echo "API exhibiting extremely poor behavior, ${percent_error}% error rate, handing over to solr-controller." 
  ./solr-controller.sh $env unavailable
 fi
 echo "Percent error on API calls; ${percent_error}%"
 echo "Percent inconsistent on API calls; ${percent_inconsistent}%"
}
echo "==== $(date)"
env=$1
sleep_time=4
api_response="./docs/api_response.txt"
api_inconsistent=0
api_unavailable=0
api_terms=( nasa women peace protest war )
if [ "$env" == "prod" ]; then
  api_env="https://catalog.archives.gov/api/v1?q="
fi
if [ "$env" == "dev" ]; then
  api_env="https://dev.research.archives.gov/api/v1?q="
fi
num_regex='[[:digit:]]*'
num_check=10
total_check=$(( ${#api_terms[@]} * ${num_check} ))
check_api
check_errors
