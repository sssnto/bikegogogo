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
一个 BikeGoGo 账号；重新绑定会自动转移归属。好友申请、申请通过、小队邀请和语音
呼叫会触发普通 APNs alert。推送失败不会回滚业务操作，APNs 确认失效的 Token 会
自动删除。

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
