# Branch-Namespaced Deployment

## Summary

This repository is a working example of Terraform modules set up to use *branch-namespaced deployment* as described in our [article here](https://hynescorp.com/pages/blog/git_namespaced_deployment).

The method is a simple technique for tightly coupling deployment environments to branches in a version control system, such that multiple developers can concurrently work in isolated staging environments, as illustrated in the diagram below:
![Site Stack](https://hynescorp.com/_static/pages/images/gitnamespaced-deployment-v1.drawio.svg)

This repository contains a snapshot of the modules for building the [hynescorp.com site stack](https://hynescorp.com/pages/blog/site_architecture) in Google Cloud.
The architeture is hopefully both complex and simple enough to be illustrative of how to use the namespaced deployment in a typical monolothic web application:

![Site Stack](https://hynescorp.com/_static/pages/images/site.architecture.drawio.svg)

## Quickstart

The `terraform` CLI is wrapped in the [`build`](build) shell script, which will run the following steps:

- Read sensitive variables from a `.env` file in the same directory
- Create a google cloud project and terraform state storage bucket for the `gcs` backend
- Run a supplied `terraform` CLI  subcommand

### Running `build`

1. **Install Prerequisites**

    - You must have the following CLI tools in your `$PATH`:
      - `gcloud`
      - `terraform`
      - `git`
    - Your current working directory must be in an initialized git repository such that `git branch --show` returns a branch name

2. **Set up your** `.env` 

    - The variables in the `.env` are examples to be replaced accordingly:

    ```bash
    export SITE_DOMAIN="example.com"
    export GOOGLE_BILLING_ACCOUNT="000000-000000-000000"
    export GOOGLE_REGION="us-west1"
    export GOOGLE_CLOUD_PROJECT_PREFIX="exdc"
    export GCS_TFSTATE_BUCKET_PREFIX="exdc-tf"
    ```

3. **Create the infrastructure**

    - The `build` script wraps all command-line arguments and passes them to `terraform`, so simply run:

    ```bash
    ./build apply
    ```
