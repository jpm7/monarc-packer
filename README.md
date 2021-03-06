# Build Automated Machine Images for MONARC

## Requirements

* [VirtualBox](https://www.virtualbox.org)
* [Packer](https://www.packer.io) from the Packer website.

## Usage

    $ export GITHUB_AUTH_TOKEN=<your-github-auth-token>
    $ packer build monarc.json

A VirtualBox image will be generated and stored in the folder
*output-virtualbox-iso*. You can directly import it in VirtualBox.

Default credentials (Web interface, SSH and MariaDB) are displayed at the end
of the process.

The sha1 and sha512 checksums of the generated VM will be stored in the files
*packer_virtualbox-iso_virtualbox-iso_sha1.checksum* and
*packer_virtualbox-iso_virtualbox-iso_sha512.checksum* respectively.

### Automatic export to GitHub

    $ GITHUB_AUTH_TOKEN=<your-github-auth-token>
    $ TAG=$(curl https://api.github.com/repos/monarc-project/MonarcAppFO/releases/latest | jq  -r '.tag_name')
    $ ./upload.sh github_api_token=$GITHUB_AUTH_TOKEN owner=monarc-project repo=MonarcAppFO tag=$TAG filename=./output-virtualbox-iso/MONARC_demo.ova

You can add these lines in the *post-processors* section of the file *monarc.json*
if you want to automate the process.
