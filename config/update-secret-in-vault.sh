#!/bin/bash

# Writes the config file that the pipeline uses when it pushes the app to 
# Cloud Foundry

vault kv put secret/weawwo config_file=@settings.yml

