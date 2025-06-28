# GCPLicenseExporter
A Bash script that will attempt to reconcile your VM's OS license 


It won't break anything, but it still takes a large amount of time to reconsile. 

Oh and MOST of the licenses hasn't been tested, and several of the License codes arn't either... 

One more thing, if there is no license code it ignroes the etire VM (otherwise it takes hours rather than minutes) - need a way to pull down the entire JSON of a Project ID rather than indivally pulling down the instance JSON

Using a combination of CLI calls and API calls, converting the CLI calls to API calls is .... not great
