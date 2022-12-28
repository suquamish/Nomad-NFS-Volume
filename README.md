# Nomad-NFS-Volume
Getting NFS up and running inside of Nomad was a bit of a challenge.

There just isn't a lot of documentation about mounting an NFS volume in Nomad,
and what I did find was already out of date because Nomad seems to be evolving
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

Setting the controller and node plugins up is pretty straight forward.  These
end up working like most other `Docker` driver job specifications. Per the
Nomad documentation "... Nomad exposes a Unix domain socket named csi.sock
inside each CSI plugin task, and communicates over the gRPC protocol expected
by the CSI specification," and you'll notice both controller and nod plugins
set the location of the "endpoint" to be a unix socket. Additionally these
are lightweight, only getting spurts of activity when specification initially
spins up, so the cpu and memory resources are **very** low. Finally, while the
controller plugin can be "centrally" located on one Nomad client, the node
plugin needs to be present on each client in your Nomad cluster, thus the
`type = "system"` designation.

Knowing all that, getting the controller and node plugins deployed should be
pretty straightforward:
---
`$ export NOMAD_ADDR=http://172.16.0.10:4646`

`$ nomad job run nfs-controller.nomad`

 <... snippage ...>
 
    Deployed
    
    Task Group  Desired  Placed  Healthy  Unhealthy  Progress Deadline
    
    plugin      1        1       1        0          2022-12-27T20:42:26-06:00
    
$

`$ nomad job run nfs-node.nomad`

 <... snippage ...>
 
    Deployed
    
    Task Group  Desired  Placed  Healthy  Unhealthy  Progress Deadline
    
    plugin      1        1       1        0          2022-12-27T20:47:12-06:00
    
$

## The creating the volume

This where things diverge from the comforts of Nomad syntax, and we dive into
Hashicorp HCL syntax. Nothing of note here, other than replace
`storage.monkeycloud.net` with the FQDNS or IP address of your nfs server.
Likewise, change `/nas/applications/mariadb` to the actual NFS share you want
to use. Beyond that, most documentation wants you to `create` the volume, in my
example, you'll want to `register` the volume, and then allocate it in a job
specification.

Take notice of the `mount_options`. This is your `/etc/fstab` entry. Particularly
the `mount_flags` options. You'll notice I've used **nolock**. That's because I
don't run `statd` and this option will keep locks "local" to the container, which
works fine for my needs. 

`$ nomad register mariadb.volume`

And you're done allocationg the volume to future usage.

## Using your nfs share in a job specification

Now you've got your plugins setup, the volume registered, time to use it in
a job specification. In my case, if you haven't caught on, I wanted a MariaDB
server running that saved all it's relevant data onto my nfs share. The
[linuxserver.io image](https://hub.docker.com/r/linuxserver/mariadb/#!) is perfect because they've configured MariaDB to house
the stateful date into the `/config` directory, which makes a for a great
mount point for our nfs volume. (maybe consider [donating to them](https://opencollective.com/linuxserver/donate?amount=20) to support their work).

Things to point out in the `mariadb.nomad` specification:
- the `volume` stanza under the `group` stanza.  This is where you allocate a
usage of your volume that you registered. The `source` is the id of the volume
you registerd in the previous section.
- the `volume_mount` section under the `task` stanza is where you actually use
the volume you just allocated.

If you get a command line on your docker container and execute the `mount`
command, you should see something like:
` <... snippage ...>`

`storage.monkeycloud.net:/nas/applications/mariadb on /config type nfs4 (rw,noatime,vers=4.0,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=172.17.0.2,local_lock=none,addr=172.16.0.100)`

` <... snippage ...>`


