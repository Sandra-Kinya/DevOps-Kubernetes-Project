# Sandra_tcs-devop-project-C

Deploy an app to a local K3s cluster, package with Helm, use Prometheus and Grafana for monitoring.

STEP 1a: INSTALL k3s
curl -sfL https://get.k3s.io | sh -

VERIFY
sudo k3s kubectl get nodes

STEP 1b: INSTALL HELM
sudo snap install helm --classic
***Helm is not available in default ubuntu package repositories

*** PERMISSION -To avoid sudo everytime
mkdir ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

STEP 2: CREATING A REPO - ***The project files will be in this directory
Added .gitignore - ***to stop junk files from getting commited

STEP 3: CREATING THE FILE STRUCTURE
mkdir -p app charts/demo-app/template

STEP 4: CREATE THE APP
cd app
nano app.py
*** I used port 8085 since port 8080 is currently being used by Jenkins - Use ss command to idenify ports.

STEP 5: CREATE DOCKERFILE
cd ..
nano Dockerfile
***COPY the correct directory app/app.py
***EXPOSE 8085

STEP 6: BUILD DOCKER IMAGE
docker build -t demo-app:v.1.0 .

STEP 7: IMPORT IMAGE INTO k3s
docker save demo-app:v.1.0 | sudo k3s ctr images import -

STEP 8: CREATE HELM CHART FILES
cd /charts/demo-app
nano chart.yaml
nano values.yaml
*** I used port 8085

STEP 9: CREATE TEMPLATE FILES
cd template
nano deployment.yaml
***If no strategy is set, kubernetes uses rolling update by default

nano service.yaml

nano _helpers.tpl - I created helpers.tpl to store reusable template functions and naming rules. *** {{ include "demo-app.name" . }} are not built-in Helm functions they only work if a _helpers.tpl file defines them.

***I changed the hardcoded service name for the fullname helper — this is necessary so the Ingress actually points at the Service I deployed

nano ingress.yaml - ***I added the kubernetes.io/ingress.class: traefik annotation

STEP 10: DEPLOY THE APP WITH HELM
cd ~/Sandra_tcs-devop-project-C
helm install demo-app ./charts/demo-app
*** Incase of changes run - helm upgrade demo-app ./charts/demo-app

NAME: demo-app
LAST DEPLOYED: Wed Jul 22 13:25:49 2026
NAMESPACE: default
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None

STEP 11: VERIFY
kubectl get pods
kubectl get svc

STEP 12: Confirm the app actually responds
kubectl port-forward svc/demo-app-demo-app 8085:8085

curl http://localhost:8085/
curl http://localhost:8085/metrics

STEP 13: TESTING INGRESS
I used K3s default traefik.
a) Confirm traefik is running: kubectl get pods -n kube-system | grep traefik 

b) Make demo.local(added to the ingress.yaml) resolve to my machine: echo "127.0.0.1 demo.local" | sudo tee -a /etc/hosts

c) Find traefik's listening port: kubectl get svc -n kube-system traefik

d) Test:
curl http://demo.local/
curl http://demo.local/metrics
 or
curl http://demo.local:31865/

STEP 14: DEMONSTRATE SELF HEALING
Kubernetes checks if there is exactly one healthy running pod (replicas:1) 

a) Confirm current health state: kubectl get pods

b) Kill pod: kubectl delete pod 

c) Immediately check pod status again: kubectl get pods
A new pod appears automatically 
***Self healing demonstration https://github.com/tcsdevopsintern/Sandra_tcs-devop-project-C/SelfHealing.mp4
 
***OPTIONAL
STEP 15: CREATE A CONFIG FILE

a) Edit app.py to read a configurable greeting message from an environment variable. The greeting message will be stored in the configMap.

b) Rebuild and reimport the image since app.py changed.
cd ~/Sandra_tcs-devop-project-C
docker build -t demo-app:v.1.0 .
docker save demo-app:v.1.0 -o demo-app.tar
sudo k3s ctr -n k8s.io images import demo-app.tar

c) Edit deployment.yaml - Add an envFrom block under the existing container spec.

d) Apply the changes
cd ~/Sandra_tcs-devop-project-C
helm upgrade demo-app ./charts/demo-app
