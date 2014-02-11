# Diary

Diary is an open-source [tent](https://tent.io) application designed to manage and edit _Essay_ posts (long-form text). Those can later be consumed by any app supporting this post type. This includes [Reevio](https://github.com/CampDev/Reevio): an _Essay_-based bloging app.

# Installation

The following instructions will guide you throughout the installation procedure on __Ubuntu__.

## Prerequisites

First things first, let's install a few dependencies for Diary to run properly.

1. NodeJS + NPM

    ```
    sudo apt-get update
    sudo apt-get install -y python-software-properties python g++ make
    sudo add-apt-repository ppa:chris-lea/node.js
    sudo apt-get update
    sudo apt-get install nodejs
    ```

2. CoffeeScript, we'll use NPM to install this one.

    ```
    sudo npm install -g coffee-script
    ```

## Diary

We're now ready to download and run Diary itself.

1. Retrieve the Diary source code from GitHub.

    ```
    git clone https://github.com/BenjBouv/diary.git
    ```
    
2. Move into the folder that you just cloned the source in, and run the following command to install all the necessary NPM packages.

    ```
    sudo npm install
    ```
    
3. Rename the sample config file `config.coffee.example` into `config.coffee`. The default port for diary to run on is _1337_, but feel free to edit this config file to change this setting.

    ```
    mv config.coffee.example config.coffee
    ```
    
4. Everything's now ready for us to run the app.

    ```
    coffee server.coffee
    ```

# License

Diary is made available under the [GPLv3](http://gplv3.fsf.org/) license.