# BikeGoGo API 设计

## 鉴权

应用支持设备绑定的访客账户和 Sign in with Apple。服务端只保存 `deviceId` 的 SHA-256
摘要，不保存设备原始标识。访问令牌是随机生成的 256 位令牌，服务端只保存令牌摘要，
默认 30 天过期；iOS 将原始令牌保存在 Keychain。

```http
POST /v1/auth/guest
Content-Type: application/json
```

```json
{
  "deviceId": "设备内持久化的 UUID",
  "displayName": "骑友-A1B2"
}
```

Apple 登录或把当前访客账户升级为 Apple 账户：

```http
POST /v1/auth/apple
Content-Type: application/json
Authorization: Bearer <当前访客 accessToken，可选>
```

```json
{
  "identityToken": "Apple 返回的签名 JWT",
  "rawNonce": "客户端本次登录生成的随机 nonce",
  "deviceId": "设备 Keychain 中的 UUID",
  "displayName": "Apple 首次授权返回的姓名"
}
```

服务端通过 Apple JWKS 验证 JWT 签名、`iss`、Bundle ID 对应的 `aud`、有效期和 nonce。
绑定已有访客会保留原用户 ID、好友码和好友关系。Apple 账户不能被另一个 Apple ID
覆盖绑定。

响应：

```json
{
  "accessToken": "随机会话令牌",
  "user": {
    "id": "usr_...",
    "displayName": "骑友-A1B2",
    "friendCode": "K7M2P9QX"
  }
}
```

除访客登录和健康检查外，账户相关接口需要：

```http
Authorization: Bearer <accessToken>
```

退出当前会话：

```http
DELETE /v1/session
Authorization: Bearer <accessToken>
```

当前用户：

```http
GET /v1/me
PATCH /v1/me
```

修改昵称请求：

```json
{
  "displayName": "周末骑手"
}
```

导出当前账户数据：

```http
GET /v1/me/export
Authorization: Bearer <accessToken>
```

响应是 JSON 文件内容，包含账户公开资料、好友、好友申请、小队和已同步骑行记录。
设备标识摘要、会话令牌及推送 token 不会进入导出文件。

永久删除当前账户：

```http
DELETE /v1/me
Authorization: Bearer <accessToken>
Content-Type: application/json
```

```json
{
  "confirmation": "DELETE",
  "appleAuthorizationCode": "Apple 重新认证返回的一次性授权码",
  "appleRawNonce": "本次重新认证使用的原始 nonce"
}
```

成功返回 `204` 并立即使该账户的全部会话失效。服务端同时删除好友申请、好友关系、
本人创建的小队、本人骑行记录、推送 token 和语音邀请；本人会从其他人创建的小队中
移除。访客账户只需要 `confirmation`。Apple 账户必须同时提供重新认证结果；服务端
验证 Apple 身份与当前账户一致，先调用 Apple REST API 撤销登录 Token，再删除数据。
缺少精确确认字符串或 Apple 重新认证信息时返回 `400`。

## 好友

```http
POST /v1/friends/requests
GET /v1/friends/requests
POST /v1/friends/requests/{requestId}/accept
POST /v1/friends/requests/{requestId}/reject
GET /v1/friends
```

发起申请：

```json
{
  "friendCode": "K7M2P9QX"
}
```

好友关系只有在接收方调用 `accept` 后建立。双方同时向对方发起申请时，第二次申请会自动
完成双向同意。

## 小队

```http
POST /v1/groups
GET /v1/groups
POST /v1/groups/{groupId}/members
DELETE /v1/groups/{groupId}/members/{userId}
DELETE /v1/groups/{groupId}
```

创建小队：

```json
{
  "name": "周末骑行队"
}
```

邀请成员：

```json
{
  "userId": "usr_..."
}
```

只有创建者可以邀请、移出成员或解散小队；被邀请人必须已经是创建者的好友。普通成员
可以通过删除自己的成员关系退出小队。每个小队当前最多 20 人。

### 小队骑行实时位置

小队成员可以在骑行页主动开启临时位置共享：

```http
PUT /v1/groups/{groupId}/live-location
Authorization: Bearer <accessToken>
Content-Type: application/json
```

```json
{
  "latitude": 39.9042,
  "longitude": 116.4074,
  "horizontalAccuracy": 8.5,
  "speed": 6.2,
  "course": 85,
  "capturedAt": "2026-07-28T08:30:00.000Z"
}
```

查询当前仍有效的小队成员位置，或主动停止共享：

```http
GET    /v1/groups/{groupId}/live-locations
DELETE /v1/groups/{groupId}/live-location
```

三个接口都要求当前账号是该小队成员，否则返回 `403`。客户端默认不开启共享，只接受
定位精度符合骑行记录要求的位置，并约每 12 秒上报、每 15 秒刷新。服务端以接收时间为准
保存最近位置，90 秒没有更新就自动过期；位置仅保存在当前服务进程内存中，不写入
PostgreSQL 或 JSON 镜像。结束骑行、手动停止共享、退出小队、被移出小队或解散小队时会
立即清除对应位置。

### 小队集合点

小队成员读取当前集合点，小队创建者设置或清除集合点：

```http
GET    /v1/groups/{groupId}/meeting-point
PUT    /v1/groups/{groupId}/meeting-point
DELETE /v1/groups/{groupId}/meeting-point
Authorization: Bearer <accessToken>
```

`PUT` 请求体：

```json
{
  "latitude": 39.9042,
  "longitude": 116.4074,
  "title": "小队集合点",
  "horizontalAccuracyMeters": 8,
  "capturedAt": "2026-07-28T03:00:00.000Z"
}
```

`GET` 对所有小队成员开放；没有有效集合点时返回 `{"meetingPoint": null}`。`PUT` 和
`DELETE` 仅允许小队创建者调用，普通成员返回 `403 group_owner_required`。集合点保存在
服务进程内存中，设置后 6 小时自动过期，解散小队或删除创建者账户时立即清除。更新成功
会向其他成员发送 `group_meeting_point_updated` APNs 通知。部署不需要新增端口、数据表
或环境变量，更新现有后端 Docker 镜像即可。

小队成员在骑行中发送紧急求助：

```http
POST /v1/groups/{groupId}/sos
Authorization: Bearer <accessToken>
Content-Type: application/json
```

请求体与 `PUT live-location` 相同。服务端会立即刷新发送者的临时位置，并向小队内除
发送者外的成员发送 `group_sos` APNs 通知。推送包含小队、发送者、坐标和采集时间，
接收端可打开 Apple 地图查看。该接口每个来源 10 分钟最多调用 3 次；非小队成员返回
`403`。SOS 及坐标不写入 PostgreSQL，位置仍按 90 秒规则自动过期。该功能只通知
BikeGoGo 小队成员，不会联系公共紧急救援服务。

## 推送设备

iOS 获取 APNs device token 后，将它绑定到当前登录账号：

```http
PUT /v1/devices/push-token
Authorization: Bearer <accessToken>
Content-Type: application/json
```

```json
{
  "token": "APNs 返回的十六进制 device token",
  "environment": "sandbox"
}
```

退出账号前使用相同请求体调用：

```http
DELETE /v1/devices/push-token
Authorization: Bearer <accessToken>
```

`sandbox` 用于 Xcode Debug 真机，`production` 用于 TestFlight/App Store。Token 只能绑定
一个 BikeGoGo 账号；重新绑定会自动转移归属。好友申请、申请通过、小队邀请、语音
呼叫、小队集合点更新和小队 SOS 会触发普通 APNs alert。推送失败不会回滚业务操作，
APNs 确认失效的 Token 会自动删除。

## 语音

发起好友或小队语音前先创建一条 90 秒有效的邀请：

```http
POST /v1/voice/invitations
Authorization: Bearer <accessToken>
Content-Type: application/json

{"targetId":"usr_... 或 grp_..."}
```

后端向好友或小队内除发起人外的所有成员发送 `voice_invitation` 推送。接收方可查询并
处理待接听邀请，发起方结束呼叫时可取消邀请：

```http
GET    /v1/voice/invitations
POST   /v1/voice/invitations/{invitationId}/respond
DELETE /v1/voice/invitations/{invitationId}
```

`respond` 请求体为 `{"action":"accept"}` 或 `{"action":"decline"}`。取消后接收方会收到
`voice_cancelled` 推送。邀请只负责呼叫状态，真正的实时音频仍通过 LiveKit 传输。

双方进入通话时，客户端通过后端换取 LiveKit token：

```http
POST /v1/voice/rooms/{friendUserId 或 groupId}/token
Authorization: Bearer <accessToken>
```

传入 `usr_...` 时，双方必须已经互相同意并成为好友；传入 `grp_...` 时，当前用户必须
是小队成员。后端生成不可直接推导的房间名，并强制使用当前账户的用户 ID 和昵称签发
2 小时 LiveKit 令牌。无会话返回 `401`，无好友或小队成员关系返回 `403`。

```json
{
  "canPublish": true,
  "canSubscribe": true
}
```

响应：

```json
{
  "url": "wss://your-livekit-host",
  "token": "livekit-jwt",
  "roomName": "group_123"
}
```

## 骑行记录

```http
GET /v1/rides
GET /v1/rides/{rideId}
PUT /v1/rides/{rideId}
DELETE /v1/rides/{rideId}
```

`PUT` 是幂等上传，URL 中的 UUID 必须与请求体 `id` 一致，且当前仅接收已经结束的
骑行记录。客户端在启动和完成骑行后上传本地记录，再拉取账号下的云端历史。

请求体示例：

```json
{
  "id": "87980d51-e579-4ac2-a494-d6e27fe2fbf7",
  "title": "本次骑行",
  "state": "finished",
  "source": "iPhone",
  "startedAt": "2026-07-27T01:00:00Z",
  "endedAt": "2026-07-27T02:15:00Z",
  "points": [
    {
      "latitude": 31.2304,
      "longitude": 121.4737,
      "elevationMeters": 8.0,
      "speedMetersPerSecond": 6.8,
      "timestamp": "2026-07-24T01:00:00Z"
    }
  ],
  "metrics": {
    "distanceMeters": 25600,
    "movingDurationSeconds": 4200,
    "elapsedDurationSeconds": 4500,
    "averageSpeedMetersPerSecond": 6.1,
    "maxSpeedMetersPerSecond": 12.8,
    "elevationGainMeters": 180
  }
}
```

每条记录最多 100,000 个轨迹点。所有读取、覆盖和删除操作都按当前账号隔离；其他账号
即使知道 ride UUID 也无法访问。
