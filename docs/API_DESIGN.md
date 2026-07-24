# BikeGoGo API 设计

## 鉴权

Apple Developer Program 审核期间，MVP 使用设备绑定的访客账户。服务端只保存
`deviceId` 的 SHA-256 摘要，并返回随机访问令牌。后续接入 Apple 登录时，保留用户 ID、
好友码和好友关系，将访客账户绑定到 Apple 身份。

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
```

## 语音

客户端通过后端换取 LiveKit token：

```http
POST /v1/voice/rooms/{groupId}/token
Authorization: Bearer <accessToken>
```

已登录客户端不需要提交 `identity` 和 `displayName`，后端会使用当前账户。旧版客户端仍可
在请求体中提交这两个字段。

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
POST /v1/rides
PATCH /v1/rides/{rideId}
POST /v1/rides/{rideId}/points:batch
GET /v1/rides
GET /v1/rides/{rideId}
```

批量上传轨迹点：

```json
{
  "points": [
    {
      "latitude": 31.2304,
      "longitude": 121.4737,
      "elevationMeters": 8.0,
      "speedMetersPerSecond": 6.8,
      "timestamp": "2026-07-24T01:00:00Z"
    }
  ]
}
```
