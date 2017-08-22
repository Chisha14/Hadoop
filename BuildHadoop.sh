#bin/bash

kubectl create namespace $3

kubectl config set-context $3 --namespace=$3

kubectl config use-context $3

kubectl run $1 --image=hash14/hadoop-nn --port=50070 --port=8088 --replicas=1 --namespace=$3

kubectl run $2 --image=hash14/hadoop-sl --replicas=$4 --namespace=$3

sleep 1

getPods="$(exec kubectl get pods --namespace=$3)"
IPmaster = "master"
echo "Pods " $getPods
master="hadoop-nn"
isRunningMaster=0
isRunningWorkers=0
runningWorkers=()
workers=()
IPs=()
for word in $getPods
do
    if [[ $word == $1* ]] ; 
    then
	master=$word
	echo "Master " $master
    elif [[ $word == $2* ]] ;
    then
	workers+=("$word") 
	echo "Workers " ${workers[@]}
    fi
done
echo "Workers ${workers[@]}"
while :
do
masterStat="$(kubectl describe pod $master --namespace=$3 | grep 'Status')"
workerStat=()

for worker in ${workers[@]}
do
workerStat+=("$(kubectl describe pod $worker --namespace=$3 | grep 'Status')")
done

for stat in $masterStat
do
	if [[ $stat == Running ]] ;
	then
		isRunningMaster=1
		echo "Master " $stat
		break
	elif [[ $stat == Pending ]]
	then
		echo "Master " $stat
		isRunning=0
	fi
done
let "i=0"
for stat in ${workerStat[@]}
do
        if [[ $stat == Running ]] ;
        then
                runningWorkers[$i]=1
                echo $i " " $stat
		let "i++"
        elif [[ $stat == Pending ]]
	then
                echo "Worker $i " $stat
                runningWorkers[$i]=0
		let "i++"
        fi
done
for i in "${runningWorkers[@]}"
do
if [[ $i -eq 0 ]] ;
then
	isRunningWorkers=0
	break
else
	isRunningWorkers=1
fi
done

if [[ $isRunningMaster -eq 1 && $isRunningWorkers -eq 1 ]] ;
then
	break
fi
sleep 2
done

IPmaster=("$(kubectl describe pod $master --namespace=$3 | grep IP | sed -E 's/IP:[[:space:]]+//')")

for ip in ${workers[@]}
do
	IPs+=("$(kubectl describe pod $ip --namespace=$3 | grep IP | sed -E 's/IP:[[:space:]]+//')")
done
echo ${IPs[@]}
echo "Workers  ${workers[@]}"
echo "Master  $IPmaster"

ssh -o StrictHostKeyChecking=no root@$IPmaster "echo -ne '<configuration>\n\t<property>\n\t\t<name>fs.defaultFS</name>\n\t\t<value>hdfs://$IPmaster:9000/</value>\n\t</property>\n</configuration>\n' > /usr/local/hadoop/etc/hadoop/core-site.xml"
ssh -o StrictHostKeyChecking=no root@$IPmaster "echo -ne '<configuration>\n\t<property>\n\t\t<name>yarn.resourcemanager.hostname</name>\n\t\t<value>$master</value>\n\t\t<description>The hostname of the RM.</description>\n\t</property>\n\t<property>\n\t\t<name>yarn.nodemanager.aux-services</name>\n\t\t<value>mapreduce_shuffle</value>\n\t</property>\t<property>\n\t\t<name>yarn.resourcemanager.hostname</name>\n\t\t<value>$master</value>\n\t</property>\n</configuration>' > /usr/local/hadoop/etc/hadoop/yarn-site.xml"

let "i=0"
for IPworkers in ${IPs[@]}
do
echo "Writing into master"
echo "adding slave$i to slaves file"
ssh -o StrictHostKeyChecking=no root@$IPmaster "echo $IPworkers >> /usr/local/hadoop/etc/hadoop/slaves"
echo "adding to /etc/hosts"
ssh -o StrictHostKeyChecking=no root@$IPmaster "echo $IPworkers    ${workers[$i]} >> /etc/hosts"

echo "writing into slave$i"
echo "writing master into /etc/hosts"
ssh -o StrictHostKeyChecking=no root@$IPworkers "echo $IPmaster    $master >> /etc/hosts"
echo "writing into core-site.xml"
ssh -o StrictHostKeyChecking=no root@$IPworkers "echo -ne '<configuration>\n\t<property>\n\t\t<name>fs.defaultFS</name>\n\t\t<value>hdfs://$IPmaster:9000/</value>\n\t</property>\n</configuration>\n' > /usr/local/hadoop/etc/hadoop/core-site.xml"
echo "writing into yarn-site.xml"
ssh -o StrictHostKeyChecking=no root@$IPworkers "echo -ne '<configuration>\n\t<property>\n\t\t<name>yarn.resourcemanager.hostname</name>\n\t\t<value>$master</value>\n\t\t<description>The hostname of the RM.</description>\n\t</property>\n\t<property>\n\t\t<name>yarn.nodemanager.aux-services</name>\n\t\t<value>mapreduce_shuffle</value>\n\t</property>\t<property>\n\t\t<name>yarn.resourcemanager.hostname</name>\n\t\t<value>$master</value>\n\t</property>\n</configuration>' > /usr/local/hadoop/etc/hadoop/yarn-site.xml"

let "i++"
done

kubectl --namespace=$3 exec -it $master sbin/start-all.sh

kubectl config set-context default --namespace=default

kubectl config use-context default

