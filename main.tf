data "terraform_remote_state" "project" {
  backend = "remote"

  config = {
    organization = "akb-test"
    workspaces = {
      name = "GCP-IOT"
    }
  }
}

provider "google" {
  credentials = data.terraform_remote_state.project.service_account_token
  project     = data.terraform_remote_state.project.short_project_id
  region = var.region

}

# ****************************************************************************
# BigQuery
# ****************************************************************************

resource "google_bigquery_dataset" "obd2info" {

    dataset_id = var.bq_dataset
    friendly_name = var.bq_dataset
    description = "Dataset containing tables related to OBD2 obdii logs"
    location = "US"

    //  user_project_override = true

   /* access {
        role = "projects/${var.gcloud_project}/roles/bigquery.admin"
        special_group = "projectOwners"
    }

    access {
        role = "projects/${var.gcloud_project}/roles/bigquery.dataEditor"
        special_group = "projectWriters"
    }

    access {
        role = "projects/${var.gcloud_project}/roles/bigquery.dataViewer"
        special_group = "projectReaders"
    }

    access {
        role = "projects/${var.gcloud_project}/roles/bigquery.jobUser"
        special_group = "projectWriters"
    }

    access {
        role = "projects/${var.gcloud_project}/bigquery.jobUser"
        special_group = "projectReaders"
    }*/
}

resource "google_bigquery_table" "obd2logging" {

    dataset_id = google_bigquery_dataset.obd2info.dataset_id
    table_id = var.bq_table


    schema = <<EOF
    [
    {
        "mode": "NULLABLE", 
        "name": "VIN", 
        "type": "STRING"
      }, 
      {
        "mode": "NULLABLE", 
        "name": "collectedAt", 
        "type": "STRING"
      }, 
      {
        "mode": "NULLABLE", 
        "name": "PID_RPM", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE", 
        "name": "PID_ENGINE_LOAD", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE", 
        "name": "PID_COOLANT_TEMP", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE", 
        "name": "PID_ABSOLUTE_ENGINE_LOAD", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE", 
        "name": "PID_TIMING_ADVANCE", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE", 
        "name": "PID_ENGINE_OIL_TEMP", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE", 
        "name": "PID_ENGINE_TORQUE_PERCENTAGE", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE",
        "name": "PID_ENGINE_REF_TORQUE", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE",   
        "name": "PID_INTAKE_TEMP", 
        "type": "FLOAT"
      },
      {
        "mode": "NULLABLE",   
        "name": "PID_MAF_FLOW", 
        "type": "FLOAT"
      },
      {
        "mode": "NULLABLE", 
        "name": "PID_BAROMETRIC", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE",  
        "name": "PID_SPEED", 
        "type": "FLOAT"
      }, 
      {
        "mode": "NULLABLE",   
        "name": "PID_RUNTIME", 
        "type": "FLOAT"
      },
      {
        "mode": "NULLABLE",   
        "name": "PID_DISTANCE", 
        "type": "FLOAT"
      }
    ]
    EOF
}

# ****************************************************************************
# PubSub
# ****************************************************************************

resource "google_pubsub_topic" "pst_obdii_data" {

    depends_on = [module.module-iot-gcp-proj]
    name = "obdii_data"
}

resource "google_pubsub_subscription" "pst_obdii_data_sub" {

    depends_on = [google_pubsub_topic.pst_obdii_data]
    name = var.pub_sub_sub
    topic = google_pubsub_topic.pst_obdii_data.name
    
    message_retention_duration = "86400s"
    retain_acked_messages = true
}

# ****************************************************************************
# IOT Core
# ****************************************************************************

resource "google_cloudiot_registry" "iot_registry" {

    depends_on = [google_pubsub_topic.pst_obdii_data, module.module-iot-gcp-proj]
    name = "obd2_devices"

    event_notification_configs {
        pubsub_topic_name = "projects/${var.gcloud_project}/topics/obdii_data"
    }
    mqtt_config = {
        mqtt_enabled_state = "MQTT_ENABLED"
    }
    http_config = {
        http_enabled_state = "HTTP_ENABLED"
    }
}


resource "google_storage_bucket" "dataflow_bucket" {
   
  name = join("",["dataflow-", var.gcloud_project])
  location = "US"

}

# ****************************************************************************
# Dataflow
# ****************************************************************************

resource "google_dataflow_job" "collect_OBD2_data" {

  name              = "OBD2-Data-Collection"
  zone = var.zone
  template_gcs_path = "gs://dataflow-templates/latest/PubSub_Subscription_to_BigQuery"
  temp_gcs_location = "${google_storage_bucket.dataflow_bucket.url}/tmp_dir"

  parameters = {
    inputSubscription = "projects/${var.gcloud_project}/subscriptions/${var.pub_sub_sub}"
    outputTableSpec = "${var.gcloud_project}:${var.bq_table}"
    #flexRSGoal = "COST_OPTIMIZED"
  }
}