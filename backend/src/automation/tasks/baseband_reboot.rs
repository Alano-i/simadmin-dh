use crate::automation::traits::AutomationTaskHandler;
use crate::state::AppState;
use crate::modem_manager::restart_baseband;
use anyhow::{Result, Context, anyhow};
use std::sync::atomic::Ordering;
use futures_util::future::{BoxFuture, FutureExt};

pub struct BasebandRebootHandler;

impl AutomationTaskHandler for BasebandRebootHandler {
    fn task_type(&self) -> &'static str {
        "restart_baseband"
    }

    fn execute<'a>(&'a self, app: &'a AppState, _params: &'a serde_json::Value) -> BoxFuture<'a, Result<()>> {
        async move {
            let auto_connect_data = !app.data_user_disabled.load(Ordering::SeqCst);
            let allow_roaming = app.config_manager.get_roaming_allowed();
            let apn_config = app.config_manager.get_apn_config();

            restart_baseband(
                &app.dbus_conn,
                auto_connect_data,
                allow_roaming,
                Some(apn_config),
            )
            .await
            .map_err(|e| anyhow!("{}", e))
            .context("重启基带失败")?;

            Ok(())
        }
        .boxed()
    }
}
