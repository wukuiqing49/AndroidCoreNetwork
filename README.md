# AndroidCoreNetwork

`AndroidCoreNetwork` 是一个基于 Retrofit、OkHttp、Gson 和 Kotlin Coroutines 的 Android 网络库，封装了统一响应处理、异常映射、动态请求头、动态 BaseUrl、上传进度、下载进度和调试日志。

仓库内包含：

- `core_network`：网络库模块。
- `app`：最小测试 Demo，点击按钮请求 `https://jsonplaceholder.typicode.com/posts/1`。

## 推荐发版方式

修改代码后优先使用自动发版脚本。脚本会自动更新文档版本、执行构建校验、发布到 Maven Local、提交代码、打 tag 并推送到远端：

```powershell
.\scripts\release-core-network.ps1 -AllowDirty
```

如果希望先手动提交功能代码，再只让脚本生成发布提交和 tag，可以先提交代码后执行：

```powershell
.\scripts\release-core-network.ps1
```

只本地生成提交和 tag、不推送：

```powershell
.\scripts\release-core-network.ps1 -AllowDirty -SkipPush
```

完整说明见 [`core_network/docs/core_network_publish.md`](core_network/docs/core_network_publish.md)。

## 引用方式

### 本工程内引用

如果业务 App 和 `core_network` 在同一个 Gradle 工程内：

```gradle
dependencies {
    implementation project(":core_network")
}
```

### JitPack 引用

发布 tag 后，使用方在项目 `settings.gradle` 添加 JitPack 仓库：

```gradle
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = "https://jitpack.io" }
    }
}
```

业务模块 `build.gradle` 添加依赖：

```gradle
dependencies {
    implementation "com.github.wukuiqing49:AndroidCoreNetwork:v1.0.4"
}
```

`v1.0.4` 需要替换成实际 Git tag。JitPack 版本号必须和 tag 完全一致。

JitPack 构建页面：

```text
https://jitpack.io/#wukuiqing49/AndroidCoreNetwork
```

### GitHub Packages 引用

项目 `settings.gradle`：

```gradle
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/wukuiqing49/AndroidCoreNetwork")
            credentials {
                username = providers.gradleProperty("gpr.user").get()
                password = providers.gradleProperty("gpr.key").get()
            }
        }
    }
}
```

业务模块 `build.gradle`：

```gradle
dependencies {
    implementation "com.github.wukuiqing49:AndroidCoreNetwork:1.0.4"
}
```

需要在本机 `~/.gradle/gradle.properties` 配置 GitHub 凭证：

```properties
gpr.user=你的GitHub用户名
gpr.key=你的GitHubToken
```

公开库优先推荐 JitPack，GitHub Packages 更适合私有或内部依赖。

## 初始化

在 `Application` 中初始化：

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()

        NetManager.init(
            NetConfig.Builder()
                .setBaseUrl("https://api.example.com/")
                .setConnectTimeout(15)
                .setReadTimeout(20)
                .setWriteTimeout(20)
                .setDebugLogsEnabled(BuildConfig.DEBUG)
                .addDefaultHeader("Accept", "application/json")
                .build()
        )
    }
}
```

`baseUrl` 必须以 `http://` 或 `https://` 开头。末尾没有 `/` 时库会自动补齐。

## 普通请求

默认响应结构是：

```kotlin
data class BaseResponse<T>(
    val code: Int = -1,
    val message: String? = null,
    val data: T? = null
)
```

`code == 200` 会被认为成功。

定义 Retrofit API：

```kotlin
interface UserApi {
    @GET("user/profile")
    suspend fun getUserProfile(): BaseResponse<User>
}
```

创建接口并请求：

```kotlin
val api = Net.create(UserApi::class.java)

when (val result = Net.request { api.getUserProfile() }) {
    is ApiResponse.Success -> {
        val user = result.data
    }
    is ApiResponse.Error -> {
        val code = result.code
        val message = result.message
        val type = result.type
    }
}
```

也可以链式处理：

```kotlin
Net.request { api.getUserProfile() }
    .onSuccess { user ->
        // 请求成功
    }
    .onError { code, message ->
        // 请求失败
    }
```

## 原始响应请求

如果接口没有 `code/message/data` 响应壳，使用 `Net.raw`：

```kotlin
interface PostApi {
    @GET("posts/{id}")
    suspend fun getPost(@Path("id") id: Int): Post
}
```

```kotlin
val result = Net.raw {
    postApi.getPost(1)
}
```

## 自定义响应解析

如果后端响应不是 `code/message/data`，实现 `NetResponseParser`：

```kotlin
data class ServerResult<T>(
    val status: Int,
    val msg: String?,
    val result: T?
)

class ServerResultParser<T> : NetResponseParser<ServerResult<T>, T> {
    override fun isSuccess(response: ServerResult<T>) = response.status == 0
    override fun code(response: ServerResult<T>) = response.status
    override fun message(response: ServerResult<T>) = response.msg
    override fun data(response: ServerResult<T>) = response.result
}
```

请求时传入 parser：

```kotlin
val result = Net.request(
    apiCall = { api.getUser() },
    parser = ServerResultParser<User>()
)
```

也可以在初始化时设置默认 parser factory：

```kotlin
NetConfig.Builder()
    .setBaseUrl("https://api.example.com/")
    .setDefaultResponseParserFactory(object : NetResponseParserFactory {
        override fun <R, T> create(): NetResponseParser<R, T> {
            return ServerResultParser<T>() as NetResponseParser<R, T>
        }
    })
    .build()
```

然后使用：

```kotlin
val result = Net.requestWithDefaultParser<ServerResult<User>, User> {
    api.getUser()
}
```

## 动态 Header

初始化时添加默认 Header：

```kotlin
NetConfig.Builder()
    .setBaseUrl("https://api.example.com/")
    .addDefaultHeader("Accept", "application/json")
    .build()
```

运行时更新 Header：

```kotlin
NetManager.headerInterceptor.addHeader("Authorization", "Bearer $token")
NetManager.headerInterceptor.removeHeader("Authorization")
NetManager.headerInterceptor.clearHeaders()
```

调试日志会自动脱敏常见敏感字段，例如 `Authorization`、`token`、`cookie`、`password`。

## 动态 BaseUrl

初始化时配置多个 BaseUrl：

```kotlin
NetManager.init(
    NetConfig.Builder()
        .setBaseUrl("https://api.example.com/")
        .putBaseUrl("user", "https://user.example.com/")
        .putBaseUrl("pay", "https://pay.example.com/")
        .build()
)
```

在 Retrofit 接口上通过 `BaseUrl-Key` 切换：

```kotlin
interface UserApi {
    @Headers("BaseUrl-Key: user")
    @GET("profile")
    suspend fun getProfile(): BaseResponse<User>
}
```

`BaseUrl-Key` 只是库内部使用的辅助 Header，请求发出前会被移除，不会传给服务端。

## 上传文件

Retrofit 接口：

```kotlin
interface UploadApi {
    @Multipart
    @POST("upload/avatar")
    suspend fun uploadAvatar(
        @Part file: MultipartBody.Part
    ): BaseResponse<String>
}
```

上传并监听进度：

```kotlin
Net.upload(file) { part ->
    uploadApi.uploadAvatar(part)
}.collect { state ->
    when (state) {
        is UploadState.Progress -> {
            val percent = state.percent
            val current = state.currentLength
            val total = state.totalLength
        }
        is UploadState.Success -> {
            val url = state.data
        }
        is UploadState.Error -> {
            val message = state.message
        }
    }
}
```

没有业务响应壳的上传接口使用：

```kotlin
Net.uploadRaw(file) { part ->
    uploadApi.uploadRaw(part)
}
```

多文件上传：

```kotlin
Net.uploadFiles(files) { parts ->
    uploadApi.uploadFiles(parts)
}
```

## 下载文件

定义接口：

```kotlin
interface DownloadApi {
    @Streaming
    @GET
    suspend fun download(@Url url: String): ResponseBody
}
```

下载到文件：

```kotlin
val api = DownloadRetrofit.create(DownloadApi::class.java)
val body = api.download(fileUrl)

body.downloadFileFlow(destFile).collect { state ->
    when (state) {
        is DownloadState.Progress -> {
            val percent = state.percent
        }
        is DownloadState.Success -> {
            val file = state.file
        }
        is DownloadState.Error -> {
            val message = state.message
        }
    }
}
```

当服务端没有返回 `Content-Length` 时，`percent` 为 `-1`，可以展示已下载字节数。

## 全局业务错误处理

可以在初始化时配置全局业务码处理器：

```kotlin
NetConfig.Builder()
    .setBaseUrl("https://api.example.com/")
    .setGlobalHandler(object : GlobalNetHandler {
        override fun onHandleBusinessCode(code: Int, message: String?): Boolean {
            if (code == 401) {
                // 例如跳转登录
                return true
            }
            return false
        }
    })
    .build()
```

即使全局处理器返回 `true`，当前请求仍会返回 `ApiResponse.Error`，方便调用方感知本次请求失败。

## 调试日志

初始化时开启：

```kotlin
NetConfig.Builder()
    .setBaseUrl("https://api.example.com/")
    .setDebugLogsEnabled(BuildConfig.DEBUG)
    .build()
```

日志会输出请求 URL、Method、Header、Query、Body、响应码、耗时和响应体。图片、视频、音频、zip、pdf、超大响应体会跳过 body 打印。

## HTTPS 说明

默认使用系统安全证书校验。调试环境如果确实需要跳过 SSL 校验：

```kotlin
NetConfig.Builder()
    .setBaseUrl("https://api.example.com/")
    .setAllowUnsafeSsl(BuildConfig.DEBUG)
    .build()
```

不要在线上环境开启 `allowUnsafeSsl`。

## 混淆

`core_network` 已配置 `consumer-rules.pro`，通过远程依赖引用时会随 AAR 传递。正常情况下使用方不需要额外添加网络库专属混淆规则。

如果业务模型被 Gson 反射解析，业务项目仍应按自己的模型规则保留必要字段。

## Demo

运行 Demo：

```powershell
.\gradlew.bat assemble
```

安装 `app` 后打开首页，点击“请求测试接口”，会通过 `core_network` 请求 `jsonplaceholder` 测试接口并展示结果。

## 发布检查

发版前建议先执行：

```powershell
.\gradlew.bat :core_network:compileDebugKotlin
.\gradlew.bat :core_network:publishReleasePublicationToMavenLocal "-PPOM_GROUP_ID=com.github.local" "-PPOM_VERSION=1.0.4"
```

完整发布说明见：

```text
core_network/docs/core_network_publish.md
```

## 自动发版脚本

修改代码后可以用脚本自动更新引用版本、构建校验、发布到 Maven Local、提交、打 tag 并推送：

```powershell
.\scripts\release-core-network.ps1 -AllowDirty
```

脚本会读取本地和远端已有 tag，默认自动执行 patch +1。例如当前最高 tag 是 `v当前版本`，会自动发布 `v下一版本`。

脚本会自动执行：

- 更新 README、发布手册和 app 示例里的 `v1.0.x` 引用。
- 执行 `:core_network:compileDebugKotlin`。
- 执行 `:app:assembleDebug -PUSE_LOCAL_CORE_NETWORK=true`，使用本地 `:core_network` 校验 Demo。
- 执行 `:core_network:publishReleasePublicationToMavenLocal`。
- `git commit -m "release core_network x.y.z"`。
- `git tag vx.y.z`。
- `git push origin main` 和 `git push origin vx.y.z`。

如果只想本地生成提交和 tag，不推送：

```powershell
.\scripts\release-core-network.ps1 -AllowDirty -SkipPush
```

指定 minor 或 major 递增：

```powershell
.\scripts\release-core-network.ps1 -Bump minor -AllowDirty
.\scripts\release-core-network.ps1 -Bump major -AllowDirty
```

也可以手动指定版本：

```powershell
.\scripts\release-core-network.ps1 -Version 1.2.3 -AllowDirty
```

脚本不会覆盖已经存在的 tag。推送完成后打开 JitPack 页面触发构建：

```text
https://jitpack.io/#wukuiqing49/AndroidCoreNetwork/v1.0.4
```
