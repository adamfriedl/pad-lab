# GCS backend — bucket created by ../scripts/bootstrap_tfstate.sh before first init.
# Init with: terraform init -backend-config="bucket=pad-lab-PROJECT-tfstate"
terraform {
  backend "gcs" {
    prefix = "pad-lab"
  }
}
