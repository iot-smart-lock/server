FROM nodered/node-red:latest
RUN npm install node-red-contrib-ttn
RUN npm install node-red-dashboard