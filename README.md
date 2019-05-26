# AnchoreJenkinsPipeline
An example Jenkins pipeline that implements Anchore to scan containers for CVE's & vulnerabilities.

<img src="https://i0.wp.com/www.upnxtblog.com/wp-content/uploads/2017/11/kubernetes.jpg" width="100"><img src="https://xebialabs.com/wp-content/uploads/2018/10/helm-logo-1.jpg" width="100"><img src="https://symbiotics.co.za/wp-content/uploads/2016/01/continuous-integration-300x300.jpeg" width="100"><img src="https://anchore.com/wp-content/uploads/2019/04/Anchore_Logo-170x54.png" width="100">

## Spin up a jenkins build server
First step is to setup a jenkins server and install a few plugins. I decided to setup a dedicated host for this, and as this isn't the most exciting thing in the world, I've scripted this process (tested on Ubuntu 18.10):

`./install_jenkins.sh`

# Deploy Anchore to a kubernetes cluster (using Helm)
All the cool kids are using Helm these days, so I figured I might as well too. Launch a Google Cloud Shell terminal window and execute the following commands:
```
gcloud container clusters create standard-cluster-1 --zone us-central1-a --num-nodes 2
gcloud container clusters get-credentials standard-cluster-1 --zone us-central1-a
```

## Install Helm
Helm helps developers define, install and manage Kubernetes applications. Helm is made up of two components, a client ('helm') and a component that runs inside the Kubernetes cluster ('Tiller'). To allow Tiller to manage applications, it needs access to the Kubernetes API, which we can enable by creating a service account and binding it to the cluster-admin role:
```
curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh
kubectl create serviceaccount -n kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller
helm init --upgrade --service-account tiller
```

## Install Anchore helm chart
For this you can do either of the steps below (they will do the same thing), I just wanted to put them here as examples

### Install Anchore with a custom values.yml file
Included in this repo is a 'anchore_values.yml' file, which contains the following config:
```
anchoreApi:
  service:
    type: LoadBalancer
```
... which will tell Helm to spin Anchor up with an externally facing LoadBalancer out of the box:


`helm install --name anchore -f anchore_values.yml stable/anchore-engine`

### Install Anchore and patch the Kubernetes service
```
helm install --name anchore stable/anchore-engine
until [ $(kubectl get pods | grep anchore-engine-api | awk '{print $3}') = "Running" ]; do ; sleep 3s ; done
kubectl patch svc "anchore-anchore-engine-api" \
    -p '{"spec": {"type": "LoadBalancer"}}'
```

Should you need it, the Anchore admin password can be retrieved with:

`kubectl get secret anchore-anchore-engine -o jsonpath --template '{.data.ANCHORE_ADMIN_PASSWORD}' | base64`

## Configure Anchore API credentials
We'll need to create some API credentials that can be used to interact with Anchor, which we can do with these commands:
```
kubectl exec -it $(kubectl get pods | grep anchore-engine-api | awk '{print $1}') -- anchore-cli account add account1 --email test@test.com
kubectl exec -it $(kubectl get pods | grep anchore-engine-api | awk '{print $1}') -- anchore-cli account user add --account account1 jenkins password123
```

# Create the build pipeline in jenkins
This git repo contains a Jenkinsfile, which contains the build pipeline config, and a Dockerfile which uses an insecure openjdk base image version as a demonstration. The Jenkinsfile (shameless ripped from: [nightfurys](https://github.com/nightfurys)) has 4 stages, which checks out the git repo, builds the Dockerfile and pushes it to a staging registry, calls Anchore to scan the built image for vulnerabilities, and finally performs some cleanup on the jenkins host. 

Head to here and follow the screenshots to configure and run the pipeline:
`http://$jenkins_ip:443/blue/organizations/jenkins`

Jenkins --> Create a new Pipeline
![](https://i.imgur.com/MA14Foi.png)

Enter the git repository where our stuff is hosted:
![](https://i.imgur.com/1v3GstC.png)

The build pipeline will attempt to run automatically, and will ask for some input parameters. Follow the 'Resolve Input' link...
![](https://i.imgur.com/yy3DnNW.png)

Enter an existing destination dockerRepository to use as a staging location. The "anchoreEngineUrl" is the address of the anchore-engine-api LoadBalancer, and can be retrieved with this command:
`kubectl get service anchore-anchore-engine-api --no-headers | awk '{print $4}'`
You'll also need to add your DockerHub and Anchore credentials we created earlier to Jenkins.
![](https://i.imgur.com/hDRtez2.png)

Jenkins continues executing the build and calls the Anchore API. This process may take a couple of minutes...
![](https://i.imgur.com/aKk7JSF.png)

The build fails when using the old openjdk image, and we can see multiple 'stop' events and multiple 'warn's. If we jump over to Jenkins classic, we can see the full report detailing each CVE that was found in the vulnerable image:
![](https://i.imgur.com/qaEjgTP.png)
![](https://i.imgur.com/ntJNldC.png)

If we then change the Dockerfile to use 'alpine:latest', we can see the build succeeds with no vulnerabilities found! :D
![](https://i.imgur.com/pUBD6dS.png)
