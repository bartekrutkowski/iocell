How to create and use templates
===============================

**Templates can save you precious time!**

Set up a jail any way you like, and create a template from it. All packages and pre-configured settings will be available for deployment next time within seconds.

Any jail can be converted to a template and back to a jail again as required. In fact a template is just another jail which has the property ``template`` set to "yes". The difference is that templates are not started by iocell.

**Here is how to create a template with iocell:**

1. Create a new jail ``iocell create tag=mytemplate``
2. Configure the jail's networking
3. Install any package you like and customize jail
4. Once finished with customization stop the jail ``iocell stop UUID | TAG``
5. A good idea is set some notes ``iocell set notes="customized PHP,nginx jail" UUID | TAG``
6. Turn the template property on ``iocell set template=yes UUID | TAG``
7. List your template with ``iocell list -t``

**Here is how to use the created template:**

To create a new jail from this template simply clone it!

1. ``iocell clone UUID-of-mytemplate tag=mynewjail``
2. List new jail ``iocell list``
3. Start jail ``iocell start UUID | TAG``

Done!

**If you need to make further customization in the template or want to patch it, you have two options.**

* convert template back to jail with ``iocell set template=no UUID-of-template``, and start the jail
* if you don't need network access to make the changes simply run ``iocell chroot UUID-of-template``, make the changes and exit
