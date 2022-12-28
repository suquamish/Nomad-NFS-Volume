# Nomad-NFS-Volume
Getting NFS up and running inside of Nomad was a bit of a challenge.

There just isn't a lot of documentation about mounting an NFS volume in Nomad,
and what I did find was already out of data because Nomad seems to be evolving
at a rapid pace.

The quick overview of what's needed:
1. an already functioning NFS server
1. a CSI NFS contoller plugin
1. a CSI NFS node plugin
1. a volume definition
1. a job specification that uses the volume

## The controller and node plugins. 
Hashicorp has a great explanation of the different kinds of storage plugins
[right here](https://developer.hashicorp.com/nomad/docs/concepts/plugins/csi), where they state:

There are three types of CSI plugins. Controller Plugins communicate with the
storage provider's APIs. [...] Node Plugins do the work on each client node,
like creating mount points. Monolith Plugins are plugins that perform both the
controller and node roles in the same instance.

One of the interesting things is that HashiCorp Nomad uses kubernetes CSI
plugins. In the example I've done, I've used a CSI plug in that that has both
controller and node plugins. It's [GitHub repository is here](https://github.com/kubernetes-csi/csi-driver-nfs).

